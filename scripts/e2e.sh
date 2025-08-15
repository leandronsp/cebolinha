#!/bin/bash

make compose.down
make processors.up
sleep 1
make processors.purge

make start.dev
sleep 2
make api.test.purge

make api.test.payments
sleep 2
make api.test.summary
