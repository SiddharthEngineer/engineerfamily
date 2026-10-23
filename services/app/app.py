from pathlib import Path

from flask import Flask, abort, send_from_directory

import admin
import auth
import perms


current_dir = Path(__file__).resolve().parent
app = Flask(__name__)
auth.init_app(app)
perms.init_app(app)
admin.init_app(app)

dist_dir = Path("/app/vite/dist")

for base in [current_dir, *current_dir.parents]:
    candidate = base / "services" / "app" / "vite" / "dist"
    if candidate.exists():
        dist_dir = candidate
        break


@app.route("/favicon.ico", defaults={"filename": "favicon.ico"})
def vite_root_static_file(filename):
    if filename != "favicon.ico" or not dist_dir.exists():
        abort(404)
    return send_from_directory(dist_dir, filename)


@app.route("/")
def home():
    return serve_vite_app()


@app.route("/assets/<path:filename>")
def vite_assets(filename):
    assets_dir = dist_dir / "assets"
    if not assets_dir.exists():
        abort(404)
    return send_from_directory(assets_dir, filename)


@app.route("/vite-app/<path:filename>")
def vite_misc_files(filename):
    if not dist_dir.exists():
        abort(404)
    return send_from_directory(dist_dir, filename)


@app.route("/games/")
def games():
    return serve_vite_app()


# The Google consent screen links here, so it must answer 200. Vite copies public/ into dist/; the source copy
# covers a checkout without a build.
@app.route("/privacy")
def privacy():
    for folder in (dist_dir, current_dir / "vite" / "public"):
        if (folder / "privacy.html").exists():
            return send_from_directory(folder, "privacy.html")
    abort(404)


def serve_vite_app():
    index_file = dist_dir / "index.html"
    if index_file.exists():
        return send_from_directory(dist_dir, "index.html")

    return (
        "Vite build not found. Run 'npm install && npm run build' in services/app/vite.",
        503,
    )


if __name__ == "__main__":
    app.run(debug=True)
