#!/bin/bash
echo "Removing existing app from Applications folder..."
rm -rf /Applications/longTerm.app
echo "Building app..."
xcodebuild -project /Users/jakeschantz/Dropbox/Mac/Desktop/longTerm/longTerm.xcodeproj -scheme longTerm -configuration Release -derivedDataPath /Users/jakeschantz/Dropbox/Mac/Desktop/longTerm/build
echo "Installing app to Applications folder..."
cp -R /Users/jakeschantz/Dropbox/Mac/Desktop/longTerm/build/Build/Products/Release/longTerm.app /Applications/
echo "Done! App has been rebuilt and installed."
