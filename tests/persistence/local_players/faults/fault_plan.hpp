// Original MIT. Qualification-only closed plans; never linked into shipping.
#pragma once
#include "flight/local_players/store_access.hpp"
#include <array>
#include <span>

namespace flight::local_players::testing {
inline constexpr std::size_t max_actions=32, max_events=524288;
enum class ActionKind : std::uint8_t { hold,fail_allocation,request_sqlite_interrupt,await_parent_process_termination };
enum class SelectorKind : std::uint8_t { operation,allocation };
struct Selector {
 SelectorKind type{SelectorKind::operation};
 std::uint64_t service{},request{};
 JobKind kind{};Scope scope{};Phase phase{};Edge edge{};std::uint64_t occurrence{};
 AllocationCategory category{};std::uint64_t ordinal{};
 friend bool operator==(const Selector&,const Selector&)=default;
};
struct Action {Selector selector{};ActionKind action{};};
// Driver freezes this roster to actual production call sites BEFORE execution.
// It is not inferred from observations or expanded automatically on a failure.
struct OperationSite {JobKind kind{};Scope scope{};Phase phase{};Edge edge{};
 friend bool operator==(const OperationSite&,const OperationSite&)=default;};
struct FaultPlan {
 std::array<Action,max_actions> actions{};std::size_t count{};
 // Pre-count ALL actual events, including allocations/partial calls/overhead.
 std::uint32_t maximum_actual_events{};
 std::span<const OperationSite> sites{};
};
bool valid_plan(const FaultPlan&) noexcept;
} // namespace flight::local_players::testing
