# SPDX-License-Identifier: PolyForm-Strict-1.0.0

from mangum import Mangum
from asgiref.wsgi import WsgiToAsgi

from dashboard.dash_app import create_dash

# Create Dash (Flask-based) app
dash_app = create_dash()

# Convert the WSGI Flask app to ASGI so Mangum can call it correctly
asgi_app = WsgiToAsgi(dash_app.server)

# Disable lifespan handling; Dash/Flask doesn't need it.
handler = Mangum(asgi_app, lifespan="off")
