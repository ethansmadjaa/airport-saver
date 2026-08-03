# airport-saver — raccourcis de dev
# make build         : compile le .saver (Debug)
# make release       : compile le .saver (Release)
# make install       : build Release + installe dans ~/Library/Screen Savers + recharge
# make install-debug : pareil mais en Debug (pour débugger)
# make check         : lance les checks CLI (topologie + machine à états piste)
# make run           : démarre l'économiseur d'écran
# make render        : rend une frame de la scène aéroport dans /tmp/airport.png

DERIVED = $(HOME)/Library/Developer/Xcode/DerivedData
SAVER   = $(HOME)/Library/Screen Savers/airport-saver.saver
SRC     = airport-saver

build:
	xcodebuild -project airport-saver.xcodeproj -scheme airport-saver -configuration Debug build | tail -3

release:
	xcodebuild -project airport-saver.xcodeproj -scheme airport-saver -configuration Release build | tail -3

install: release
	rm -rf "$(SAVER)"
	cp -R "$$(ls -d $(DERIVED)/airport-saver-*/Build/Products/Release/airport-saver.saver | head -1)" "$(HOME)/Library/Screen Savers/"
	-killall legacyScreenSaver ScreenSaverEngine 2>/dev/null
	@echo "installé (Release) — sélectionne airport-saver dans Réglages > Économiseur d'écran"

install-debug: build
	rm -rf "$(SAVER)"
	cp -R "$$(ls -d $(DERIVED)/airport-saver-*/Build/Products/Debug/airport-saver.saver | head -1)" "$(HOME)/Library/Screen Savers/"
	-killall legacyScreenSaver ScreenSaverEngine 2>/dev/null
	@echo "installé (Debug) — sélectionne airport-saver dans Réglages > Économiseur d'écran"

check:
	swiftc -o /tmp/topology_check $(SRC)/ScreenTopology.swift checks/topology_check.swift && /tmp/topology_check
	swiftc -o /tmp/runway_check $(SRC)/RunwayPlane.swift checks/runway_check.swift && /tmp/runway_check

run:
	open -a ScreenSaverEngine

render:
	swiftc -o /tmp/render $(SRC)/PixelCanvas.swift $(SRC)/PixelScene.swift $(SRC)/Sprites.swift $(SRC)/RunwayPlane.swift $(SRC)/ScreenTopology.swift $(SRC)/AirportScene.swift $(SRC)/SkyScene.swift $(SRC)/FlightCoordinator.swift checks/render.swift
	/tmp/render airport /tmp/airport.png 480 10
	open /tmp/airport.png

.PHONY: build release install install-debug check run render
