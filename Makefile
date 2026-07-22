PROJECT = Echo.xcodeproj
SCHEME  = Echo
XCB     = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug

.PHONY: build test coverage run clean

build:
	$(XCB) build

test:
	$(XCB) test

coverage:
	rm -rf build/Echo.xcresult
	$(XCB) -resultBundlePath build/Echo.xcresult test
	xcrun xccov view --report --only-targets build/Echo.xcresult

run:
	$(XCB) -derivedDataPath build build
	open build/Build/Products/Debug/Echo.app

clean:
	rm -rf build
	$(XCB) clean
