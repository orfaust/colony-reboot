package logic

import "core:testing"

@(test)
station_stock_bounds :: proc(t: ^testing.T) {
    testing.expect(t, valid_station_stock(0,0,0))
    testing.expect(t, valid_station_stock(10,10,2))
    testing.expect(t, valid_station_stock(4.5,10,-0.5))
    testing.expect(t, !valid_station_stock(-1,10,0))
    testing.expect(t, !valid_station_stock(11,10,0))
    testing.expect(t, !valid_station_stock(0,-1,0))
    infinity := transmute(f32)u32(0x7f800000)
    nan := transmute(f32)u32(0x7fc00000)
    testing.expect(t, !valid_station_stock(infinity,infinity,0))
    testing.expect(t, !valid_station_stock(0,infinity,0))
    testing.expect(t, !valid_station_stock(0,10,nan))
    testing.expect(t, !valid_station_stock(0,10,infinity))
}
