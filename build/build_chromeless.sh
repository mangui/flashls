#!/bin/bash
if [ -z "$FLEXPATH" ]; then
  echo "Usage FLEXPATH=/path/to/flex/sdk sh ./build.sh"
  exit
fi

OPT_DEBUG="-use-network=false \
    -optimize=true \
    -define=CONFIG::LOGGING,true \
    -define=CONFIG::FLASH_11_1,true"

echo "Compiling bin/debug/flashlsChromeless.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/chromeless/ChromelessPlayer.as \
    -source-path ../src \
    -o ../bin/debug/flashlsChromeless.swf \
    $OPT_DEBUG \
    -library-path+=../lib/blooddy_crypto.swc \
    -target-player="11.1" \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/debug/flashlsChromeless.swf
