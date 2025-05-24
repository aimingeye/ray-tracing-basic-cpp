#!/bin/bash

set -e  # Exit on error

echo "Compiling Metal shader..."
xcrun -sdk macosx metal -c Raytracer.metal -o Raytracer.air

echo "Linking Metal library..."
xcrun -sdk macosx metallib Raytracer.air -o Raytracer.metallib

echo "Compiling Objective-C++ application..."
clang++ -std=c++17 -framework Metal -framework Foundation -framework MetalKit raytracergpu.mm -o raytracergpu

echo "✅ Build completed successfully!"
