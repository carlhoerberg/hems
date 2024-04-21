#!/bin/bash -eux

protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/device.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/common/status/status.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/command.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/common.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/dish.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/wifi.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/wifi_config.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/transceiver.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/common.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/dish_config.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/satellites/network/ut_disablement_codes.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/wifi_util.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/telemetron/public/common/time.proto
protoc --ruby_out=lib/ --descriptor_set_in=dish.protoset spacex/api/device/services/unlock/service.proto
find lib/spacex/ -type f | xargs sed -i'' "s|require 'spacex|require_relative '../../../spacex|"
