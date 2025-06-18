#!/bin/bash

curl -X POST http://localhost:8080/wp-json/presskit.core/v1/presentation/product \
    -H "Content-Type: application/json" \
    -d '{"title": "A Fine Product", "description": "A fine product description"}'


curl -X POST http://localhost:8080/wp-json/presskit.core/v1/presentation/product | jq