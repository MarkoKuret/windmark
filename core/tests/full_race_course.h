// The course of the full-race tests (race.md §12, WM-009), without doctest so tools can use it too: a one-lap
// windward-leeward on the shipped example venue with an exclusion zone in the race area.
#pragma once

namespace wm_test {

inline const char* kFullRaceCourse = R"({
  "schema": "windmark.course/1", "id": "test_wl_1", "name": "Test windward-leeward, 1 lap", "venue": "example_bay",
  "frame": "wind", "reference": { "x": 0.0, "y": -300.0 },
  "marks": [
    { "id": "rc",  "type": "committee_boat", "at": { "bearing": 1.57079633, "dist": 90, "fixed": true } },
    { "id": "pin", "type": "buoy", "style": "tetra", "at": { "bearing": 4.71238898, "dist": 90, "fixed": true } },
    { "id": "w",   "type": "buoy", "style": "large", "at": { "bearing": 0, "dist": 320, "from": "rc_pin_mid", "fixed": true } },
    { "id": "gc",  "type": "virtual", "at": { "bearing": 3.14159265, "dist": 90, "from": "rc_pin_mid", "fixed": true } },
    { "id": "g1",  "type": "buoy", "at": { "bearing": 1.57079633, "dist": 30, "from": "gc", "fixed": true } },
    { "id": "g2",  "type": "buoy", "at": { "bearing": 4.71238898, "dist": 30, "from": "gc", "fixed": true } }
  ],
  "start": { "ends": ["pin", "rc"] },
  "finish": "start",
  "sequence": [ { "mark": "w", "round": "port" }, { "gate": ["g1", "g2"] } ],
  "area": { "boundary": [ { "x": -900, "y": -1100 }, { "x": 900, "y": -1100 }, { "x": 900, "y": 700 }, { "x": -900, "y": 700 } ],
            "exclusions": [ { "id": "lane", "polygon": [ { "x": 220, "y": -420 }, { "x": 420, "y": -420 },
                                                        { "x": 420, "y": -150 }, { "x": 220, "y": -150 } ] } ] },
  "race": { "type": "fleet", "sequence": "3-2-1-0", "prep_flag": "I", "time_limit": 1500 }
})";

}  // namespace wm_test
