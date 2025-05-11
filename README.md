# cse-dashboard

## Overview

This project is a serverless financial dashboard for quarterly data, hosted on AWS Lambda and accessible at [https://cse-dashboard.amod.dev](https://cse-dashboard.amod.dev).

---

## Technologies Used

- **Dash by Plotly**: Interactive Python web app framework for data visualization.
- **AWS Lambda**: Serverless compute for scalable, pay-per-use hosting.
- **Mangum**: ASGI adapter to run Dash (Flask/WSGI) apps on AWS Lambda.
- **asgiref**: Used to wrap the WSGI app for ASGI compatibility.
- **Docker**: For reproducible, multi-arch builds and deployment.
- **Pandas**: Data manipulation and analysis.
- **Parquet**: Efficient, compressed, columnar data storage.
- **Dash Bootstrap Components**: For responsive, modern UI.

---

## Why Parquet Instead of CSV?

- **Performance**: Parquet is a binary, columnar format that loads much faster than CSV, especially for large datasets.
- **Compression**: Parquet files are much smaller on disk, reducing cold-start time and Lambda package size.
- **Schema**: Parquet preserves data types and schema, avoiding type inference errors common with CSV.
- **Example**: A 200MB CSV can often be reduced to a 40MB Parquet file and load in milliseconds instead of seconds.

---

## Serverless Handler and Mangum

- **handler.py**: Entry point for AWS Lambda. It wraps the Dash app using `WsgiToAsgi` and Mangum so Lambda can invoke it as an ASGI app.
- **Mangum**: A Python library that adapts ASGI (and WSGI via asgiref) applications to AWS Lambda, enabling serverless deployment of Dash, FastAPI, and other Python web frameworks.

---

## Running Locally

To run the dashboard locally for development:

1. Install dependencies (Python 3.13+ recommended):
   ```sh
   uv sync
   ```
2. Start the app:
   ```sh
   python run_dash.py
   ```
3. Visit [http://localhost:8050](http://localhost:8050) in your browser.

---

## Licensing

This repository is licensed under the **PolyForm Strict License 1.0.0**:

- **No redistribution**
- **No modification**
- **No commercial use**
- **Source-available for personal, research, and noncommercial institutional use only**

See [LICENSE](LICENSE) for full terms.

Copyright © 2025 Amod