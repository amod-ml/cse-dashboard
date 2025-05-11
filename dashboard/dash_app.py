# SPDX-License-Identifier: PolyForm-Strict-1.0.0

from __future__ import annotations

from pathlib import Path
from functools import lru_cache

import pandas as pd
import plotly.express as px
import dash
from dash import Dash, Input, Output, State, callback, dcc, html, ALL
import dash_bootstrap_components as dbc
from dash.dash_table import DataTable

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
LIGHT_THEME = dbc.themes.LUX
DARK_THEME = dbc.themes.CYBORG


@lru_cache(maxsize=1)
def load_parquets() -> pd.DataFrame:
    """Load and cache all parquet files under DATA_DIR.

    Using an LRU cache ensures the expensive disk IO and deserialization only
    occur once per cold-start, which shaves a noticeable slice off the first
    request latency without affecting memory use in warm invocations.
    """
    dfs = [pd.read_parquet(fp) for fp in DATA_DIR.glob("*.parquet")]
    if not dfs:
        raise FileNotFoundError("No parquet files in data/")
    return pd.concat(dfs, ignore_index=True).assign(
        period_end_date=lambda d: pd.to_datetime(d["period_end_date"], unit="ms")
    )


def kpi_card(title: str, value: str) -> dbc.Card:
    """Reusable KPI pill."""
    return dbc.Card(
        dbc.CardBody(
            [
                html.H6(title, className="card-title"),
                html.H4(value, className="card-text"),
            ]
        ),
        class_name="text-center shadow-sm",
    )


def themed_table(is_dark: bool, **kwargs) -> DataTable:
    if is_dark:
        style_header = {'backgroundColor': 'rgb(30, 30, 30)', 'color': 'white'}
        style_data = {'backgroundColor': 'rgb(50, 50, 50)', 'color': 'white'}
    else:
        style_header = {'backgroundColor': 'rgb(230, 230, 230)', 'color': '#212529'}
        style_data = {'backgroundColor': 'white', 'color': '#212529'}
    return DataTable(
        style_header=style_header,
        style_data=style_data,
        **kwargs
    )


def create_dash() -> Dash:
    df_all = load_parquets()
    companies = sorted(df_all["company_name"].unique())

    external_stylesheets = [LIGHT_THEME]  # start in light mode
    app = dash.Dash(
        __name__,
        requests_pathname_prefix="/",  # root when served from Lambda function URL
        external_stylesheets=external_stylesheets,
        suppress_callback_exceptions=True,
    )

    app.layout = html.Div(
        id="theme-root",
        className="theme-root",
        children=[
            dbc.Container(
                [
                    dcc.Store(id="theme-store", data={"dark": False}),
                    dbc.Row(
                        [
                            dbc.Col(
                                html.H2("Quarterly Financial Dashboard"), class_name="col-auto"
                            ),
                            dbc.Col(
                                dbc.Switch(id="dark-toggle", label="🌙 Dark Mode", value=False),
                                class_name="col-auto align-self-center",
                            ),
                        ],
                        class_name="my-3 g-3",
                    ),
                    dbc.Row(
                        [
                            dbc.Col(
                                dcc.Dropdown(
                                    id="company-dd",
                                    options=[{"label": c, "value": c} for c in companies],
                                    value=companies[0],
                                    clearable=False,
                                    persistence=True,
                                    style={"minWidth": "260px"},
                                ),
                                md=4,
                            ),
                            dbc.Col(
                                dcc.DatePickerRange(
                                    id="date-range",
                                    min_date_allowed=df_all["period_end_date"].min(),
                                    max_date_allowed=df_all["period_end_date"].max(),
                                    start_date=df_all["period_end_date"].min(),
                                    end_date=df_all["period_end_date"].max(),
                                    persistence=True,
                                ),
                                md=4,
                            ),
                            dbc.Col(
                                dcc.Dropdown(
                                    id="metric-dd",
                                    multi=True,
                                    options=[
                                        {"label": m.replace("_", " ").title(), "value": m}
                                        for m in [
                                            "revenue",
                                            "gross_profit",
                                            "profit_before_tax",
                                            "net_income_parent",
                                        ]
                                    ],
                                    value=["revenue", "gross_profit", "profit_before_tax", "net_income_parent"],
                                    persistence=True,
                                ),
                                md=4,
                            ),
                        ],
                        class_name="g-3",
                    ),
                    dbc.Spinner(
                        [
                            dbc.Row(
                                [
                                    dbc.Col(kpi_card("Revenue (Rs '000)", "--"), id="kpi-rev"),
                                    dbc.Col(kpi_card("Gross Profit", "--"), id="kpi-gp"),
                                    dbc.Col(kpi_card("Net Income", "--"), id="kpi-net"),
                                ],
                                class_name="my-4 g-3",
                            ),
                            dcc.Graph(id="trend-chart"),
                            themed_table(False, id="table", page_size=10, style_table={"overflowX": "auto"}, export_format="csv"),
                        ]
                    ),
                ],
                fluid=True,
            )
        ]
    )

    @callback(
        Output("theme-store", "data", allow_duplicate=True),
        Input("dark-toggle", "value"),
        prevent_initial_call=True,
    )
    def _toggle_theme(is_dark: bool) -> dict:
        return {"dark": is_dark}

    @callback(
        Output("theme-root", "className"),
        Input("theme-store", "data"),
    )
    def update_theme_root_class(theme_state: dict) -> str:
        return "theme-root dark-mode" if theme_state.get("dark") else "theme-root"

    @callback(
        Output("trend-chart", "figure"),
        Output("table", "data"),
        Output("table", "style_header"),
        Output("table", "style_data"),
        Output("kpi-rev", "children"),
        Output("kpi-gp", "children"),
        Output("kpi-net", "children"),
        Input("company-dd", "value"),
        Input("date-range", "start_date"),
        Input("date-range", "end_date"),
        Input("metric-dd", "value"),
        Input("theme-store", "data"),
        memoize=True,  # Dash 2.16 memoisation for snappier updates
    )
    def _update(
        company: str,
        start: str,
        end: str,
        metrics: list[str],
        theme_state: dict,
    ) -> tuple:
        dff = df_all.query(
            "company_name == @company and @start <= period_end_date <= @end"
        )

        # line chart
        fig = px.line(
            dff,
            x="period_end_date",
            y=metrics,
            markers=True,
            template="plotly_dark" if theme_state["dark"] else "plotly_white",
            title=f"{company} - Selected metrics",
        )
        fig.update_layout(
            yaxis_title="Rs '000",
            xaxis_title="Period End",
            xaxis={"rangeslider": {"visible": True}},
        )

        # KPI latest quarter
        latest = dff.sort_values("period_end_date").iloc[-1]
        kpi_rev = kpi_card("Revenue (Rs '000)", f"{latest.revenue:,.0f}")
        kpi_gp = kpi_card("Gross Profit", f"{latest.gross_profit:,.0f}")
        kpi_net = kpi_card("Net Income", f"{latest.net_income_parent:,.0f}")

        is_dark = theme_state.get("dark", False)
        if is_dark:
            style_header = {'backgroundColor': 'rgb(30, 30, 30)', 'color': 'white'}
            style_data = {'backgroundColor': 'rgb(50, 50, 50)', 'color': 'white'}
        else:
            style_header = {'backgroundColor': 'rgb(230, 230, 230)', 'color': '#212529'}
            style_data = {'backgroundColor': 'white', 'color': '#212529'}

        return fig, dff.to_dict("records"), style_header, style_data, kpi_rev, kpi_gp, kpi_net

    @callback(
        Output({"type": "theme-style", "index": ALL}, "style"),
        Input("theme-store", "data"),
        State({"type": "theme-style", "index": ALL}, "style"),
    )
    def _swap_css(theme_state: dict, styles: list[dict]) -> list[dict]:
        theme_href = DARK_THEME if theme_state["dark"] else LIGHT_THEME
        app._external_stylesheets = [theme_href]  # pylint: disable=protected-access
        return styles

    return app
