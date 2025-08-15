#!/bin/bash

make compose.down
make processors.up
make processors.purge

make start.dev
make api.test.purge
