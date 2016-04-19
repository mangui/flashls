@echo off

IF "%FLEX_HOME%"=="" ( echo Please set FLEX_HOME to the path of the Flex SDK && GOTO end )
IF "%JAVA_HOME%"=="" ( echo Please set JAVA_HOME to the path of the Java SDK && GOTO end ) ELSE ( GOTO build )

:build

cls

IF "%1"=="" (set BIN_PATH=..\bin) ELSE (set BIN_PATH=%1)

echo Building SWF/SWC files into %BIN_PATH%
echo.

if not exist "%BIN_PATH%\release" mkdir "%BIN_PATH%\release"
if not exist "%BIN_PATH%\debug" mkdir "%BIN_PATH%\debug"

set OPT_DEBUG=-use-network=false ^
    -debug=true ^
    -library-path+=..\lib\blooddy_crypto.swc ^
    -define+=CONFIG::LOGGING,true

set OPT_RELEASE=-use-network=false ^
    -debug=false ^
    -optimize=true ^
    -library-path+=..\lib\blooddy_crypto.swc ^
    -define+=CONFIG::LOGGING,false

echo Compiling bin\debug\flashls.swc...
call "%FLEX_HOME%\bin\compc" ^
    %OPT_DEBUG% ^
    -include-sources ..\src\org\mangui\hls ^
    -output %BIN_PATH%\debug\flashls.swc ^
    -target-player=10.1

echo.
echo Compiling bin\release\flashls.swc...
call "%FLEX_HOME%\bin\compc" ^
    %OPT_RELEASE% ^
    -include-sources ..\src\org\mangui\hls ^
    -output %BIN_PATH%\release\flashls.swc ^
    -target-player=10.1

echo.
echo Compiling bin\release\flashlsChromeless.swf...
call "%FLEX_HOME%\bin\mxmlc" ..\src\org\mangui\chromeless\ChromelessPlayer.as ^
    -source-path+=..\src ^
    -o %BIN_PATH%\release\flashlsChromeless.swf ^
    %OPT_RELEASE% ^
    -target-player=11.1 ^
    -default-size 480 270 ^
    -default-background-color=0x000000
.\add-opt-in.py %BIN_PATH%\release\flashlsChromeless.swf

echo.
echo Compiling bin\debug\flashlsChromeless.swf...
call "%FLEX_HOME%\bin\mxmlc" ..\src\org\mangui\chromeless\ChromelessPlayer.as ^
    -source-path+=..\src ^
    -o %BIN_PATH%\debug\flashlsChromeless.swf ^
    %OPT_DEBUG% ^
    -target-player=11.1 ^
    -default-size 480 270 ^
    -default-background-color=0x000000
REM .\add-opt-in.py %BIN_PATH%\debug\flashlsChromeless.swf

echo.
echo Compiling bin\release\flashlsFlowPlayer.swf...
call "%FLEX_HOME%\bin\mxmlc" ..\src\org\mangui\flowplayer\HLSPluginFactory.as ^
    -source-path+=..\src -o %BIN_PATH%\release\flashlsFlowPlayer.swf ^
    %OPT_RELEASE% ^
    -library-path+=..\lib\flowplayer ^
    -load-externs=..\lib\flowplayer\flowplayer-classes.xml ^
    -target-player=11.1
REM .\add-opt-in.py %BIN_PATH%\release\flashlsFlowPlayer.swf

echo.
echo Compiling bin\debug\flashlsFlowPlayer.swf...
call "%FLEX_HOME%\bin\mxmlc" ..\src\org\mangui\flowplayer\HLSPluginFactory.as ^
    -source-path+=..\src -o %BIN_PATH%\debug\flashlsFlowPlayer.swf ^
    %OPT_DEBUG% ^
    -library-path+=..\lib\flowplayer ^
    -load-externs=..\lib\flowplayer\flowplayer-classes.xml ^
    -target-player=11.1
.\add-opt-in.py %BIN_PATH%\debug\flashlsFlowPlayer.swf

echo.
echo Compiling bin\release\flashlsOSMF.swf...
call "%FLEX_HOME%\bin\mxmlc" ..\src\org\mangui\osmf\plugins\HLSDynamicPlugin.as ^
    -source-path+=..\src ^
    -o %BIN_PATH%\release\flashlsOSMF.swf ^
    %OPT_RELEASE% ^
    -library-path+=..\lib\osmf ^
    -load-externs=..\lib\osmf\exclude-sources.xml ^
    -target-player=10.1
.\add-opt-in.py %BIN_PATH%\release\flashlsOSMF.swf

echo.
echo Compiling bin\debug\flashlsOSMF.swf...
call "%FLEX_HOME%\bin\mxmlc" ..\src\org\mangui\osmf\plugins\HLSDynamicPlugin.as ^
    -source-path+=..\src ^
    -o %BIN_PATH%\debug\flashlsOSMF.swf ^
    %OPT_DEBUG% ^
    -library-path+=..\lib\osmf ^
    -load-externs=..\lib\osmf\exclude-sources.xml ^
    -target-player=10.1
.\add-opt-in.py %BIN_PATH%\debug\flashlsOSMF.swf

echo.
echo Compiling bin\release\flashlsOSMF.swc...
call "%FLEX_HOME%\bin\compc" ^
    -include-sources ..\src\org\mangui\osmf ^
    -output %BIN_PATH%\release\flashlsOSMF.swc ^
    %OPT_RELEASE% ^
    -library-path+=%BIN_PATH%\release\flashls.swc ^
    -library-path+=..\lib\osmf ^
    -target-player=10.1 ^
    -external-library-path+=..\lib\osmf

echo.
echo Compiling bin\debug\flashlsOSMF.swc...
call "%FLEX_HOME%\bin\compc" ^
    -include-sources ..\src\org\mangui\osmf ^
    -output %BIN_PATH%\debug\flashlsOSMF.swc ^
    %OPT_DEBUG% ^
    -library-path+=%BIN_PATH%\debug\flashls.swc ^
    -library-path+=..\lib\osmf ^
    -target-player=10.1 ^
    -external-library-path+=..\lib\osmf

:end

echo.
pause
