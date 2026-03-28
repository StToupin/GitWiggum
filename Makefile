# Optional IHP bundling inputs for static/prod.css and static/prod.js.
# Files in static/ are served directly without being listed here.
CSS_FILES += static/base.css

JS_FILES += static/vendor/htmx.min.js
JS_FILES += static/vendor/morphdom-umd.min.js
JS_FILES += static/helpers-htmx.js
JS_FILES += static/htmx-instant-click.js
JS_FILES += static/pull-request-attachments-loader.js
JS_FILES += static/pull-request-attachments.js
JS_FILES += static/ihp-auto-refresh-htmx.js
JS_FILES += static/google-login.js

include ${IHP}/Makefile.dist

.PHONY: FORCE

build/Generated/Types.hs: FORCE

FORCE:
