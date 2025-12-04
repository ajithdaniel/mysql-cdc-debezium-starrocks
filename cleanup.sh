#!/bin/bash

# Cleanup CDC Pipeline

echo "========================================"
echo "Cleaning up CDC Pipeline"
echo "========================================"

echo "Stopping all containers..."
docker-compose down

read -p "Do you want to remove all volumes (data will be lost)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "Removing volumes..."
    docker-compose down -v
    echo "All volumes removed."
else
    echo "Volumes preserved."
fi

echo "========================================"
echo "Cleanup complete!"
echo "========================================"
