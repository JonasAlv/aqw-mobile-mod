#!/bin/bash
VERSION=$1
# strip v from v3.5.0
VERSION=${VERSION#v}
sed -i "s|<versionNumber>.*</versionNumber>|<versionNumber>${VERSION}</versionNumber>|" loader/Mobile-app.xml
sed -i "s|<versionNumber>.*</versionNumber>|<versionNumber>${VERSION}</versionNumber>|" loader/Desktop-app.xml
