#!/bin/bash
if [ -z "$FLEXPATH" ]; then
  echo "Usage FLEXPATH=/path/to/flex/sdk sh ./build.sh"
  exit
fi

OPT_DEBUG="-use-network=false \
    -optimize=true \
    -debug=true \
    -library-path+=../lib/blooddy_crypto.swc \
    -define=CONFIG::LOGGING,true \
    -define=CONFIG::FLASH_11_1,true"

OPT_RELEASE="-use-network=false \
    -optimize=true \
    -debug=false \
    -library-path+=../lib/blooddy_crypto.swc \
    -define=CONFIG::LOGGING,false \
    -define=CONFIG::FLASH_11_1,true"

echo "Compiling bin/release/flashlsChromeless.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/chromeless/ChromelessPlayer.as \
    -source-path ../src \
    -o ../bin/release/flashlsChromeless.swf \
    $OPT_RELEASE \
    -target-player="11.1" \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/release/flashlsChromeless.swf

echo "Compiling bin/debug/flashlsChromeless.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/chromeless/ChromelessPlayer.as \
    -source-path ../src \
    -o ../bin/debug/flashlsChromeless.swf \
    $OPT_DEBUG \
    -target-player="11.1" \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/debug/flashlsChromeless.swf
