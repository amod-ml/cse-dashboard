# SPDX-License-Identifier: PolyForm-Strict-1.0.0

from dashboard.dash_app import create_dash

app = create_dash()
app.run(host="0.0.0.0", port=8050, debug=True)
