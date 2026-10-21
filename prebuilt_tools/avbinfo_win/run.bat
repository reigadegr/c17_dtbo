@echo off
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo 请把镜像文件拖拽到此 .bat 上执行
    pause
    exit /b
)

set input_file=%~1

set output_file=%~dpn1.txt

python3 avbtool.py info_image --image "%input_file%" --output "%output_file%"
pause