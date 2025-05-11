# SPDX-License-Identifier: PolyForm-Strict-1.0.0

from mangum import Mangum
from dashboard.dash_app import create_dash

dash_app = create_dash()

handler = Mangum(dash_app.server)
