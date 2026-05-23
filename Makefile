

virtual-env:
	virtualenv .venv
	(. .venv/bin/activate && pip install -e recipes)

install:
	(. .venv/bin/activate && pip install -e recipes)

back-dev:
	(. .venv/bin/activate && FLASK_STATIC=$(pwd) uvicorn okaasan.server.run:entry --reload --host 0.0.0.0 --port 5001)

back-prod:
	(. .venv/bin/activate && uvicorn okaasan.server.run:entry --host 0.0.0.0 --port 8081)

front-dev:
	(cd recipes/okaasan/ui && npm i && npm run dev)

preprocess-images:
	(. .venv/bin/activate && FLASK_STATIC=$(pwd) python -m okaasan.tools.preprocess_images)

update-db:
	(. .venv/bin/activate && DATABASE_URI=sqlite://$(pwd)/database.db alembic -c recipes/okaasan/alembic/alembic.ini upgrade head)

make-migration:
	(. .venv/bin/activate && DATABASE_URI=sqlite://$(pwd)/database.db alembic -c recipes/okaasan/alembic/alembic.ini revision --autogenerate -m "migration")

current:
	(. .venv/bin/activate && DATABASE_URI=sqlite://$(pwd)/database.db alembic -c recipes/okaasan/alembic/alembic.ini current)


telegram:
	(. .venv/bin/activate && python recipes/okaasan/server/messaging.py)

test-deploy:
	(. .venv/bin/activate && FLASK_STATIC=$(pwd) python recipes/scripts/static_generator.py)


deploy-dev:
	(. .venv/bin/activate && uv pip install -e /home/setepenre/work/website/recipes)
	sudo cp deploy/okasan-flask.service /etc/systemd/system/okasan-flask.service
	sudo cp deploy/okasan-vite.service /etc/systemd/system/okasan-vite.service
	sudo cp deploy/okasan.target /etc/systemd/system/okasan.target

start-services:
	sudo systemctl enable okasan.target
	sudo systemctl start okasan.target

update-services: deploy-dev
	sudo systemctl daemon-reload
	sudo systemctl restart okasan.target

kill-flask:
	@pgrep -f "[u]vicorn okaasan.server.run:entry" | xargs -r kill && echo "okaasan server killed" || echo "no okaasan server running"

kill:
	@pgrep -f "[u]vicorn okaasan.server.run:entry" | xargs -r kill && echo "okaasan server killed" || echo "no okaasan server running"
	@pgrep -f "[c]vlc.*--intf dummy" | xargs -r kill && echo "VLC processes killed" || echo "no VLC processes running"

flask-logs:
	sudo journalctl -u okasan-flask.service -f

vite-logs:
	sudo journalctl -u okasan-vite.service -f

update-nginx:
	sudo cp deploy/nginx-recipes.conf /etc/nginx/sites-enabled/recipes
	sudo nginx -t && sudo systemctl reload nginx
	@echo "Nginx config updated."

install-garmin-udev:
	chmod +x deploy/garmin_import.sh
	sudo cp deploy/99-garmin.rules /etc/udev/rules.d/99-garmin.rules
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	@echo "Garmin USB auto-import rule installed. Plug in your watch to test."


# ---- Garmin udev ----

check-garmin-udev:
	@echo "=== Rule file ==="
	@test -f /etc/udev/rules.d/99-garmin.rules && echo "OK: rule installed" || echo "MISSING: run 'make install-garmin-udev'"
	@echo ""
	@echo "=== Rule syntax check ==="
	@sudo udevadm verify /etc/udev/rules.d/99-garmin.rules 2>&1 || true
	@echo ""
	@echo "=== pyusb available ==="
	@.venv/bin/python3 -c "import usb.core; print('OK: pyusb installed')" 2>/dev/null || echo "MISSING: pip install pyusb"
	@echo ""
	@echo "=== Connected Garmin devices ==="
	@lsusb 2>/dev/null | grep -i "091e\|garmin" || echo "No Garmin device currently connected"
	@echo ""
	@echo "=== Mount point ==="
	@mount | grep /mnt/garmin || echo "/mnt/garmin not mounted (normal if watch is unplugged)"
	@echo ""
	@echo "=== Recent udev logs (last 20 lines for Garmin) ==="
	@sudo journalctl -u systemd-udevd --since "1 hour ago" --no-pager 2>/dev/null | grep -i "garmin\|091e\|mnt/garmin" | tail -20 || true
	@echo ""
	@echo "=== Recent server USB import logs ==="
	@sudo journalctl -u okasan-flask.service --since "1 hour ago" --no-pager 2>/dev/null | grep -i "usb.import\|usb_import\|USB import" | tail -10 || true
	@echo ""
	@echo "=== Server reachable ==="
	@curl -sf -o /dev/null http://localhost:5001/health-data/usb-garmin/status && echo "OK: server responds" || echo "FAIL: server not reachable at localhost:5001"
