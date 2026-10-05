// Racing rules scenarios (rules.md §13): two or three scripted boats, headless, with the expected obligation,
// states and penalties.
#include <cmath>
#include <string>
#include <vector>

#include "course/geometry.h"
#include "rules_harness.h"

using namespace wm_test;
using wm::KcState;
using wm::RuleCode;
using wm::Vec2;

namespace {

constexpr float kBeat = 45.0f * 0.0174532924f;

// Starboard boat S (0) at (0, 400) close-hauled; port boat P (1) close-hauled on a course that meets S's track
// `lead` seconds after S passes the meeting point (negative: P arrives first).
RulesRig port_starboard(float lead, float v = 3.0f) {
  RulesRig rig(2);
  const float ps = heading_for(0.0f, kBeat), pp = heading_for(0.0f, -kBeat);
  const float T = 12.0f;
  const Vec2 S0{0.0f, 400.0f};
  const Vec2 meet = wm::v_add(S0, wm::v_scale(wm::dir(ps), v * T));
  const Vec2 P0 = wm::v_sub(meet, wm::v_scale(wm::dir(pp), v * (T + lead)));
  rig.b[0] = {S0, ps, v, 0.0f};
  rig.b[1] = {P0, pp, v, 0.0f};
  rig.to_prep();
  return rig;
}

}  // namespace

TEST_CASE("rules: port and starboard on a beat") {
  SUBCASE("port boat ducks: clear") {
    RulesRig rig = port_starboard(4.0f);
    rig.watch(25.0f);
    const wm::PairRecord* r = nullptr;
    (void)r;
    CHECK(rig.max_kc(0, 1) == KcState::clear);
    CHECK(rig.penalties(1) == 0);
    CHECK(rig.penalties(0) == 0);
  }
  SUBCASE("port boat on a collision course, crosses ahead after the warning: no penalty") {
    RulesRig rig = port_starboard(0.0f);
    // Warned 1 to 4 s out, the port boat bears away hard to pass astern.
    bool warned = false;
    for (int k = 0; k < 500; ++k) {
      rig.watch_step();
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (!warned && r != nullptr && r->kc_state == KcState::warning) {
        warned = true;
        CHECK(r->kc_giver == 1);
        CHECK(r->kc_rule == RuleCode::r10);
        rig.b[1].psi = wm::wrap_2pi(rig.b[1].psi + 60.0f * wm::DEG);  // bears away onto a reach, well clear
      }
    }
    CHECK(warned);
    CHECK(rig.max_kc(0, 1) == KcState::warning);
    CHECK(rig.count(wm::RulesEventKind::rule_warning, 1) >= 1);
    CHECK(rig.penalties(1) == 0);
  }
  SUBCASE("port boat forces starboard to bear away: rule 10") {
    RulesRig rig = port_starboard(0.0f);
    for (int k = 0; k < 500; ++k) {
      rig.watch_step();
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (r != nullptr && r->kc_state == KcState::breach && rig.b[0].r == 0.0f && rig.penalties(1) == 0) {
        // S keeps her course a little, then bears away to avoid the collision.
      }
      if (rig.penalties(1) > 0 && rig.b[0].r == 0.0f) rig.b[0].r = -20.0f * wm::DEG;
      if (std::fabs(wm::angle_diff(rig.b[0].psi, heading_for(0.0f, kBeat))) > 60.0f * wm::DEG) rig.b[0].r = 0.0f;
    }
    CHECK(rig.max_kc(0, 1) == KcState::breach);
    CHECK(rig.penalties(1, RuleCode::r10) == 1);
    CHECK(rig.penalties(0) == 0);
    CHECK(rig.rules.boat(1).pending.size() == 1);
  }
  SUBCASE("collision: rule 10 at once") {
    RulesRig rig = port_starboard(0.0f);
    bool hit = false;
    for (int k = 0; k < 500; ++k) {
      rig.watch_step();
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (!hit && r != nullptr && r->kc_state == KcState::breach) {
        rig.touch(0, wm::ContactKind::boat, 1, 2.5f);
        hit = true;
      }
    }
    REQUIRE(hit);
    CHECK(rig.penalties(1, RuleCode::r10) == 1);
    // A damaging contact, and the starboard boat did nothing: she is penalised under 14 as well.
    CHECK(rig.penalties(0, RuleCode::r14) == 1);
    bool contact_incident = false;
    for (const wm::RulesEvent& e : rig.events) {
      if (e.kind == wm::RulesEventKind::incident && e.boat == 1 && e.contact) contact_incident = true;
    }
    CHECK(contact_incident);
  }
}

TEST_CASE("rules: rule 16, the starboard boat changing course") {
  SUBCASE("bears away onto a ducking port boat: 16.2") {
    RulesRig rig = port_starboard(2.5f);
    rig.watch(8.0f);  // 4 s before S passes the meeting point
    REQUIRE(rig.max_kc(0, 1) == KcState::clear);
    rig.b[0].r = -15.0f * wm::DEG;
    rig.watch(2.0f);
    rig.b[0].r = 0.0f;
    rig.watch(10.0f);
    CHECK(rig.penalties(0, RuleCode::r16_2) == 1);
    CHECK(rig.penalties(1) == 0);
  }
  SUBCASE("luffs into a port boat crossing ahead with no escape: 16.1") {
    RulesRig rig = port_starboard(-4.0f);
    rig.watch(8.5f);
    REQUIRE(rig.max_kc(0, 1) != KcState::breach);
    rig.b[0].r = 40.0f * wm::DEG;
    rig.watch(1.0f);
    rig.b[0].r = 0.0f;
    rig.watch(10.0f);
    CHECK(rig.penalties(0, RuleCode::r16_1) == 1);
    CHECK(rig.penalties(1) == 0);
  }
  SUBCASE("luffs earlier; the port boat could have kept clear: rule 10") {
    RulesRig rig = port_starboard(-4.0f);
    rig.watch(7.5f);
    rig.b[0].r = 40.0f * wm::DEG;
    rig.watch(1.0f);
    rig.b[0].r = 0.0f;
    rig.watch(10.0f);
    CHECK(rig.penalties(0) == 0);
    CHECK(rig.penalties(1, RuleCode::r10) == 1);
  }
}

TEST_CASE("rules: tacking too close") {
  // Both on port close-hauled; T (0) is ahead of Q (1), `ahead` m between the reference points and `right` m to
  // leeward, and tacks onto starboard across Q's bow.
  auto setup = [](float rate, float t_speed, float ahead, float right) {
    RulesRig rig(2);
    const float pp = heading_for(0.0f, -kBeat);
    const Vec2 f = wm::dir(pp);
    const Vec2 Q0{-20.0f, 380.0f};
    const Vec2 T0 = wm::v_add(wm::v_add(Q0, wm::v_scale(f, ahead)), wm::v_scale({f.y, -f.x}, right));
    rig.b[0] = {T0, pp, 3.0f, 0.0f};
    rig.b[1] = {Q0, pp, 3.5f, 0.0f};
    rig.to_prep();
    rig.b[0].r = -rate;  // turning to port, through the wind
    rig.b[0].v = t_speed;
    return rig;
  };
  SUBCASE("the port boat cannot avoid her while she tacks: 13") {
    RulesRig rig = setup(15.0f * wm::DEG, 1.0f, 14.4f, 0.0f);
    bool tacking_seen = false;
    for (int k = 0; k < 400; ++k) {
      rig.watch_step();
      tacking_seen = tacking_seen || rig.rules.boat(0).tacking;
      if (std::fabs(wm::angle_diff(rig.b[0].psi, heading_for(0.0f, kBeat))) < 2.0f * wm::DEG) rig.b[0].r = 0.0f;
    }
    CHECK(tacking_seen);
    CHECK(rig.penalties(0, RuleCode::r13) == 1);
    CHECK(rig.penalties(1) == 0);
  }
  SUBCASE("tack completed farther ahead: the port boat could keep clear, rule 10") {
    RulesRig rig = setup(90.0f * wm::DEG, 1.5f, 12.0f, 3.0f);
    for (int k = 0; k < 400; ++k) {
      rig.watch_step();
      if (std::fabs(wm::angle_diff(rig.b[0].psi, heading_for(0.0f, kBeat))) < 5.0f * wm::DEG) {
        rig.b[0].r = 0.0f;
        rig.b[0].psi = heading_for(0.0f, kBeat);
      }
    }
    CHECK(rig.penalties(0) == 0);
    CHECK(rig.penalties(1, RuleCode::r10) == 1);
  }
  SUBCASE("tack completed, the port boat still has no escape: 15 against the tacker") {
    RulesRig rig = setup(90.0f * wm::DEG, 1.5f, 10.0f, 3.0f);
    for (int k = 0; k < 400; ++k) {
      rig.watch_step();
      if (std::fabs(wm::angle_diff(rig.b[0].psi, heading_for(0.0f, kBeat))) < 5.0f * wm::DEG) {
        rig.b[0].r = 0.0f;
        rig.b[0].psi = heading_for(0.0f, kBeat);
      }
    }
    CHECK(rig.penalties(0, RuleCode::r15) == 1);
    CHECK(rig.penalties(0, RuleCode::r13) == 0);
    CHECK(rig.penalties(1) == 0);
  }
}

TEST_CASE("rules: rule 17, proper course of a leeward boat from clear astern") {
  // Starboard tack close-hauled; the leeward boat L (1) comes up from clear astern to leeward of W (0).
  auto setup = [](float lateral, float v_leeward) {
    RulesRig rig(2);
    const float ps = heading_for(0.0f, kBeat);
    const Vec2 f = wm::dir(ps);
    const Vec2 left{-f.y, f.x};  // leeward on starboard tack is to the left
    const Vec2 W0{50.0f, 300.0f};
    const Vec2 L0 = wm::v_add(wm::v_sub(W0, wm::v_scale(f, 12.0f)), wm::v_scale(left, lateral));
    rig.b[0] = {W0, ps, 3.0f, 0.0f};
    rig.b[1] = {L0, ps, v_leeward, 0.0f};
    rig.to_prep();
    return rig;
  };
  SUBCASE("overlap within 2 L, then luffs above her proper course: 17") {
    RulesRig rig = setup(9.0f, 4.0f);
    for (int k = 0; k < 400 && rig.rules.pair(0, 1) == nullptr; ++k) rig.step();
    int flagged = 0;
    for (int k = 0; k < 600; ++k) {
      rig.watch_step();
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (r != nullptr && r->rule17_holder == 1) ++flagged;
      if (flagged == 20 && rig.b[1].r == 0.0f) rig.b[1].r = 10.0f * wm::DEG;  // luff to 25 degrees
      if (std::fabs(wm::wrap_pi(0.0f - rig.b[1].psi)) < 25.0f * wm::DEG) rig.b[1].r = 0.0f;
      if (rig.penalties(1) > 0) break;
    }
    CHECK(flagged > 0);
    CHECK(rig.penalties(1, RuleCode::r17) == 1);
    CHECK(rig.penalties(0) == 0);
  }
  SUBCASE("overlap established from 3 L to leeward: no flag, she may luff") {
    RulesRig rig = setup(22.0f, 3.3f);
    bool flagged = false;
    for (int k = 0; k < 400; ++k) {
      rig.watch_step();
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (r != nullptr && r->rule17_holder >= 0) flagged = true;
    }
    CHECK(!flagged);
    rig.b[1].r = 10.0f * wm::DEG;
    for (int k = 0; k < 600; ++k) {
      rig.watch_step();
      if (std::fabs(wm::wrap_pi(0.0f - rig.b[1].psi)) < 25.0f * wm::DEG) rig.b[1].r = 0.0f;
    }
    CHECK(rig.penalties(1) == 0);
    CHECK(rig.penalties(0, RuleCode::r11) == 1);  // the windward boat did not keep clear
  }
}

TEST_CASE("rules: barging at the committee boat") {
  // Before the start, starboard tack, running down the line towards the committee boat at (100, 0): the windward
  // boat W (0) squeezes in between the leeward boat L (1) and the committee boat.
  RulesRig rig(2);
  const float ps = heading_for(0.0f, kBeat);
  rig.b[1] = {{80.0f, -25.0f}, ps, 3.0f, 0.0f};
  rig.b[0] = {{88.0f, -19.0f}, wm::wrap_2pi(ps - 10.0f * wm::DEG), 3.2f, 0.0f};
  rig.to_prep();
  rig.watch(15.0f);
  CHECK(rig.penalties(0, RuleCode::r11) == 1);
  CHECK(rig.penalties(1) == 0);
  for (const wm::PairRecord& r : rig.rules.pairs()) CHECK(r.room_rule == RuleCode::none);
}

TEST_CASE("rules: rule 22") {
  SUBCASE("an OCS boat returning hits a starting boat: 22.1") {
    RulesRig rig(2);
    rig.b[0] = {{0.0f, -30.0f}, 0.0f, 0.0f, 0.0f};
    rig.b[1] = {{20.0f, -30.0f}, 0.0f, 0.0f, 0.0f};
    rig.to_prep();
    rig.b[0].p = {0.0f, 5.0f};  // over the line at the gun
    while (rig.n <= rig.gun()) rig.step();
    REQUIRE(rig.race.boat(0).ocs);
    rig.b[0] = {{0.0f, 5.0f}, wm::PI, 2.0f, 0.0f};       // returning, heading south
    rig.b[1] = {{1.5f, -12.0f}, 0.0f, 2.0f, 0.0f};       // starting, heading north
    bool hit = false;
    for (int k = 0; k < 200; ++k) {
      rig.watch_step();
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (r != nullptr && !hit && r->gap < 0.2f) {
        CHECK(r->kc_rule == RuleCode::r21_1);
        CHECK(r->kc_giver == 0);
        rig.touch(0, wm::ContactKind::boat, 1, 1.0f);
        hit = true;
      }
    }
    CHECK(hit);
    CHECK(rig.penalties(0, RuleCode::r21_1) == 1);
    CHECK(rig.penalties(1) == 0);
  }
  SUBCASE("a boat doing a penalty turn hits another: 22.2") {
    RulesRig rig(2);
    rig.b[0] = {{-40.0f, 300.0f}, heading_for(0.0f, kBeat), 3.0f, 0.0f};
    rig.b[1] = {{-40.0f, 330.0f}, heading_for(0.0f, kBeat), 3.0f, 0.0f};
    rig.to_prep();
    rig.touch(0, wm::ContactKind::mark, 2);  // not a mark she may touch yet: no penalty before her start
    rig.step();
    CHECK(rig.penalties(0) == 0);
    // Give boat 0 a penalty by touching the pin before starting (a starting mark).
    rig.touch(0, wm::ContactKind::mark, 1);
    rig.step();
    REQUIRE(rig.penalties(0, RuleCode::r31) == 1);
    rig.b[0].r = -20.0f * wm::DEG;
    bool turning = false;
    const std::uint32_t t_pen = rig.n;
    for (int k = 0; k < 200; ++k) {
      rig.watch_step();
      turning = turning || rig.rules.boat(0).turning_for_penalty;
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (turning && r != nullptr && r->kc_rule == RuleCode::r21_2 && rig.n > t_pen + 70) {
        CHECK(r->kc_giver == 0);
        rig.touch(0, wm::ContactKind::boat, 1, 1.0f);
        rig.step();
        break;
      }
    }
    CHECK(turning);
    CHECK(rig.penalties(0, RuleCode::r21_2) == 1);
  }
}

TEST_CASE("rules: penalty turns, deadline and disqualification") {
  auto penalised = []() {
    RulesRig rig(1);
    rig.b[0] = {{-40.0f, -150.0f}, heading_for(0.0f, kBeat), 3.0f, 0.0f};
    rig.to_prep();
    rig.touch(0, wm::ContactKind::mark, 1);  // the pin before starting: rule 31
    rig.step();
    REQUIRE(rig.rules.boat(0).pending.size() == 1);
    return rig;
  };
  SUBCASE("a 360 with a tack and a gybe serves it") {
    RulesRig rig = penalised();
    rig.b[0].r = -20.0f * wm::DEG;
    rig.run(19.0f);
    CHECK(rig.count(wm::RulesEventKind::penalty_served, 0) == 1);
    CHECK(rig.rules.boat(0).pending.empty());
    CHECK(rig.rules.boat(0).served == 1);
  }
  SUBCASE("a 360 with a 4 s pause does not") {
    RulesRig rig = penalised();
    rig.b[0].r = -20.0f * wm::DEG;
    rig.run(9.0f);
    rig.b[0].r = 0.0f;
    rig.run(4.0f);
    rig.b[0].r = -20.0f * wm::DEG;
    rig.run(9.0f);
    CHECK(rig.count(wm::RulesEventKind::penalty_served, 0) == 0);
    CHECK(rig.rules.boat(0).pending.size() == 1);
  }
  SUBCASE("fleet race: a turn inside the zone of the next mark counts") {
    RulesRig rig(1);
    rig.start_at({{{0.0f, 990.0f}, heading_for(0.0f, kBeat), 3.0f, 0.0f}});
    rig.touch(0, wm::ContactKind::mark, 2);  // the windward mark, her next mark: rule 31
    rig.step();
    REQUIRE(rig.rules.boat(0).pending.size() == 1);
    rig.b[0].p = {12.0f, 985.0f};  // within 3 L of the mark
    rig.b[0].v = 1.0f;
    rig.b[0].r = -20.0f * wm::DEG;
    rig.run(19.0f);
    CHECK(rig.count(wm::RulesEventKind::penalty_served, 0) == 1);
  }
  SUBCASE("match race: a turn inside the zone of the next mark does not (Appendix C)") {
    wm::RaceSettings ms = quick_settings();
    ms.race_type = wm::RaceType::match;
    ms.sequence = wm::SequenceKind::match;
    RulesRig rig(2, ms);
    CHECK(rig.race.zone_lengths() == 2.0f);
    rig.start_at({{{0.0f, 990.0f}, heading_for(0.0f, kBeat), 3.0f, 0.0f},
                  {{-90.0f, 700.0f}, heading_for(0.0f, kBeat), 0.0f, 0.0f}});
    rig.run(0.5f);
    REQUIRE(rig.rules.boat(1).pending.empty());
    rig.touch(0, wm::ContactKind::mark, 2);  // the windward mark: rule 31
    rig.step();
    REQUIRE(rig.rules.boat(0).pending.size() == 1);
    CHECK(rig.rules.boat(0).deadline_s < 0.0f);  // one penalty in a match: no deadline
    rig.b[0].p = {8.0f, 988.0f};  // within 2 L of the mark
    rig.b[0].v = 1.0f;
    rig.b[0].r = -20.0f * wm::DEG;
    rig.run(19.0f);
    CHECK(rig.count(wm::RulesEventKind::penalty_served, 0) == 0);
  }
  SUBCASE("a pause only to keep clear under 21.2 does not reset the turn") {
    wm::RaceSettings ps = quick_settings();
    ps.umpire = wm::UmpireMode::protest;  // the 21.2 breach of the pause is not penalised on its own
    RulesRig rig(2, ps);
    rig.b[0] = {{-40.0f, -150.0f}, heading_for(0.0f, kBeat), 3.0f, 0.0f};
    rig.b[1] = {{60.0f, -150.0f}, 0.0f, 0.0f, 0.0f};
    rig.to_prep();
    rig.touch(0, wm::ContactKind::mark, 1);
    rig.step();
    REQUIRE(rig.rules.boat(0).pending.size() == 1);
    rig.b[0].r = -20.0f * wm::DEG;
    rig.run(9.0f);
    REQUIRE(rig.rules.boat(0).turning_for_penalty);
    // Boat 1 comes slowly at her bow; she stops turning to keep clear for 4 s.
    rig.b[0].r = 0.0f;
    rig.b[0].v = 0.0f;
    const wm::Vec2 f = wm::dir(rig.b[0].psi);
    rig.b[1] = {wm::v_add(rig.b[0].p, wm::v_scale(f, 9.2f)), wm::wrap_2pi(rig.b[0].psi + wm::PI), 0.5f, 0.0f};
    bool kept_clear = false;
    for (int k = 0; k < 80; ++k) {
      rig.step();
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (r != nullptr && r->kc_rule == RuleCode::r21_2 && r->kc_giver == 0 && r->kc_state != KcState::clear)
        kept_clear = true;
    }
    CHECK(kept_clear);
    rig.b[1].v = 0.0f;
    rig.b[0].v = 3.0f;
    rig.b[0].r = -20.0f * wm::DEG;
    rig.run(10.0f);
    CHECK(rig.count(wm::RulesEventKind::penalty_served, 0) == 1);
    CHECK(rig.rules.boat(0).pending.empty());
  }
  SUBCASE("not completed within 120 s of the incident: disqualified, no extra penalty") {
    RulesRig rig = penalised();
    rig.run(110.0f);
    CHECK(rig.rules.boat(0).pending.size() == 1);
    CHECK(rig.rules.boat(0).deadline_s > 9.0f);
    CHECK(rig.rules.boat(0).deadline_s < 10.5f);
    // A turn still in progress when the time runs out does not save her.
    rig.b[0].r = -20.0f * wm::DEG;
    rig.run(10.5f);
    CHECK(rig.count(wm::RulesEventKind::penalty_served, 0) == 0);
    CHECK(rig.count(wm::RulesEventKind::penalty_late, 0) == 1);
    CHECK(rig.count(wm::RulesEventKind::disqualified, 0) == 1);
    CHECK(rig.penalties(0) == 1);
    CHECK(rig.rules.boat(0).dsq);
    CHECK(rig.race.boat(0).code == wm::ScoreCode::DSQ);
    for (const wm::RulesEvent& e : rig.events) {
      if (e.kind == wm::RulesEventKind::disqualified) CHECK(e.rule == RuleCode::late);
    }
  }
  SUBCASE("three pending: disqualified") {
    RulesRig rig = penalised();
    rig.run(3.5f);
    rig.touch(0, wm::ContactKind::course_object, 0);  // the committee boat, a starting mark
    rig.step();
    rig.run(3.5f);
    rig.run(10.0f);
    rig.touch(0, wm::ContactKind::mark, 1);  // the pin again, 10 s later
    rig.step();
    CHECK(rig.count(wm::RulesEventKind::disqualified, 0) == 1);
    CHECK(rig.rules.boat(0).dsq);
    CHECK(rig.race.boat(0).ghost);
    CHECK(rig.race.boat(0).code == wm::ScoreCode::DSQ);
  }
}

TEST_CASE("rules: mark touches") {
  RulesRig rig(1);
  rig.start_at({{{0.0f, 900.0f}, heading_for(0.0f, kBeat), 3.0f, 0.0f}});
  rig.touch(0, wm::ContactKind::mark, 3);  // l, not a mark of her leg
  rig.step();
  CHECK(rig.penalties(0) == 0);
  rig.touch(0, wm::ContactKind::mark, 2);  // w, her next mark
  rig.step();
  CHECK(rig.penalties(0, RuleCode::r31) == 1);
  CHECK(rig.count(wm::RulesEventKind::mark_touch, 0) == 1 + 0);
  rig.run(4.0f);
  rig.touch(0, wm::ContactKind::mark, 2);  // again within 10 s: no second penalty
  rig.step();
  CHECK(rig.penalties(0, RuleCode::r31) == 1);
}

TEST_CASE("rules: a mark touch and a Part 2 breach in one incident owe the Part 2 penalty (44.1(a))") {
  RulesRig rig = port_starboard(-1.0f);
  rig.touch(1, wm::ContactKind::mark, 1);  // the port boat touches the pin before starting: rule 31
  rig.step();
  REQUIRE(rig.penalties(1, RuleCode::r31) == 1);
  const std::uint32_t t31 = rig.rules.boat(1).pending.front().tick;
  rig.run(1.0f);
  rig.touch(1, wm::ContactKind::boat, 0);  // and hits the starboard boat 1 s later: rule 10
  rig.step();
  CHECK(rig.penalties(1, RuleCode::r10) == 1);
  CHECK(rig.count(wm::RulesEventKind::penalty_cancelled, 1) == 1);
  REQUIRE(rig.rules.boat(1).pending.size() == 1);
  CHECK(rig.rules.boat(1).pending.front().rule == RuleCode::r10);
  CHECK(rig.rules.boat(1).pending.front().tick == t31);
  CHECK(rig.rules.boat(1).pending.front().count == 1);
  CHECK(rig.rules.boat(1).received == 1);
}

TEST_CASE("rules: the same scenario gives the same events") {
  auto run = []() {
    RulesRig rig = port_starboard(-1.0f);
    rig.b[0].r = 4.0f * wm::DEG;
    rig.run(30.0f);
    std::vector<std::uint64_t> sig;
    for (const wm::RulesEvent& e : rig.events) {
      sig.push_back((static_cast<std::uint64_t>(e.tick) << 24) ^ (static_cast<std::uint64_t>(e.kind) << 16) ^
                    (static_cast<std::uint64_t>(e.rule) << 8) ^ static_cast<std::uint64_t>(e.boat + 1));
    }
    return sig;
  };
  const std::vector<std::uint64_t> a = run(), b = run();
  CHECK(!a.empty());
  CHECK(a == b);
}


namespace {

// One mark m (0, 300) to port, approached running south from above; the finish line is at y = 600.
std::string mark_course() {
  return R"({"schema": "windmark.course/1", "id": "t", "name": "T", "venue": "v", "frame": "world",
    "marks": [{"id": "rc", "type": "buoy", "at": {"x": 100, "y": 0}},
              {"id": "pin", "type": "buoy", "at": {"x": -100, "y": 0}},
              {"id": "m", "type": "buoy", "at": {"x": 0, "y": 300}},
              {"id": "f1", "type": "buoy", "at": {"x": -60, "y": 600}},
              {"id": "f2", "type": "buoy", "at": {"x": 60, "y": 600}}],
    "start": {"ends": ["pin", "rc"]}, "finish": {"ends": ["f1", "f2"]},
    "sequence": [{"mark": "m", "round": "port"}]})";
}

}  // namespace

// Two boats on port tack broad-reaching (heading 150) to m, to be left to port: the inside boat 0 on a track `off`
// m to the right of the mark, the outside boat 1 `lat` m further right and `back` m behind.
struct Reach {
  Vec2 inside, outside;
  float h;
};
Reach reach(float off, float lat, float back, float dist = 45.0f) {
  const float h = 150.0f * wm::DEG;
  const Vec2 d = wm::dir(h), right{d.y, -d.x};
  const Vec2 M{0.0f, 300.0f};
  const Vec2 I0 = wm::v_add(wm::v_sub(M, wm::v_scale(d, dist)), wm::v_scale(right, off));
  const Vec2 O0 = wm::v_sub(wm::v_add(I0, wm::v_scale(right, lat)), wm::v_scale(d, back));
  return {I0, O0, h};
}

TEST_CASE("rules: mark-room at a port-rounding mark") {
  const Vec2 M{0.0f, 300.0f};
  SUBCASE("overlapped at the zone, the outside boat squeezes the inside: 18.2") {
    RulesRig rig(2, quick_settings(), mark_course());
    const Reach g = reach(4.0f, 6.0f, -1.0f, 18.0f);
    const Vec2 d = wm::dir(g.h), right{d.y, -d.x};
    const float hi = wm::compass(wm::v_sub(wm::v_add(M, wm::v_scale(right, 4.0f)), g.inside));
    const float ho = wm::compass(wm::v_sub(wm::v_add(M, wm::v_scale(right, 1.0f)), g.outside));
    rig.start_at({{g.inside, hi, 3.0f, 0.0f}, {g.outside, ho, 3.0f, 0.0f}});
    rig.step();
    const wm::PairRecord* r = rig.rules.pair(0, 1);
    REQUIRE(r != nullptr);
    CHECK(r->room_entitled == 0);
    CHECK(r->room_giver == 1);
    CHECK(r->room_rule == RuleCode::r18_2);
    CHECK(r->kc_giver == 0);  // the inside boat is windward: she keeps clear under 11 but is owed mark-room
    rig.run(8.0f);
    CHECK(rig.penalties(1, RuleCode::r18_2) == 1);
    CHECK(rig.penalties(0) == 0);
  }
  SUBCASE("the inside boat sails wide outside her corridor and hits: no exoneration") {
    RulesRig rig(2, quick_settings(), mark_course());
    const Reach g = reach(8.0f, 6.0f, 0.0f);
    rig.start_at({{g.inside, g.h, 3.0f, 0.0f}, {g.outside, g.h, 3.0f, 0.0f}});
    rig.run(8.0f);
    const wm::PairRecord* r = rig.rules.pair(0, 1);
    REQUIRE(r != nullptr);
    CHECK(r->room_entitled == 0);
    rig.b[0].psi = g.h + 20.0f * wm::DEG;  // away from the mark, into the outside boat
    bool hit = false;
    for (int k = 0; k < 200; ++k) {
      rig.step();
      const wm::PairRecord* q = rig.rules.pair(0, 1);
      if (q != nullptr && !hit && q->gap < 0.2f) {
        rig.touch(0, wm::ContactKind::boat, 1, 1.0f);
        hit = true;
      }
    }
    CHECK(hit);
    CHECK(rig.penalties(0, RuleCode::r11) == 1);
    CHECK(rig.penalties(1) == 0);
  }
  SUBCASE("clear astern at the zone, inside overlap late: no mark-room") {
    RulesRig rig(2, quick_settings(), mark_course());
    const Reach g = reach(8.0f, 6.0f, -14.0f);  // the outside boat 14 m ahead
    rig.start_at({{g.inside, g.h, 4.0f, 0.0f}, {g.outside, g.h, 3.0f, 0.0f}});
    bool overlapped_late = false, inside_entitled = false;
    for (int k = 0; k < 300; ++k) {
      rig.step();
      const wm::PairRecord* r = rig.rules.pair(0, 1);
      if (r == nullptr || r->room_rule == RuleCode::none) continue;
      if (r->room_entitled == 0) inside_entitled = true;
      if (r->relation == wm::Relation::overlapped && r->room_entitled == 1) overlapped_late = true;
    }
    CHECK(overlapped_late);
    CHECK(!inside_entitled);
  }
  SUBCASE("tacking onto starboard in the zone, forcing a starboard boat above close-hauled: 18.3") {
    const wm::PolarVmg v = wm::polar_vmg(perf("wm7"), 5.0f);
    RulesRig rig(2, quick_settings(), mark_course());
    const float hs = heading_for(0.0f, v.up_twa), hp = heading_for(0.0f, -v.up_twa);
    const Vec2 T0{10.0f, 292.0f};
    const Vec2 S0 = wm::v_sub(T0, wm::v_scale(wm::dir(hs), 9.0f));
    rig.start_at({{T0, hp, 2.5f, 0.0f}, {S0, hs, 3.0f, 0.0f}});
    rig.b[0].r = -90.0f * wm::DEG;
    rig.b[0].v = 1.0f;
    for (int k = 0; k < 200; ++k) {
      rig.step();
      if (std::fabs(wm::angle_diff(rig.b[0].psi, hs)) < 5.0f * wm::DEG) {
        rig.b[0].r = 0.0f;
        rig.b[0].psi = hs;
      }
    }
    CHECK(rig.penalties(0, RuleCode::r18_3) == 1);
    CHECK(rig.penalties(1) == 0);
  }
}
