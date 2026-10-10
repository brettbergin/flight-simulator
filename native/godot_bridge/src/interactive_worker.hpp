#pragma once
#include <flight/interactive/session.hpp>
#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <mutex>
#include <optional>
#include <thread>

namespace flight::bridge {
struct InteractiveReply {
  std::string aircraft, atmosphere, fault;
  // Open-only metadata sampled through the actual getter on the owner worker.
  std::optional<std::string> angular_method;
  interactive::c::PilotAxes held;
  std::vector<std::string> commands, events;
  std::uint64_t event_sequence{};
  interactive::Status status{interactive::Status::completed};
  int completed{}, rejection{};
  bool live{}, paused{}, queued{}, ground_valid{};
  double time_scale{1}, surface_height_m{}, clearance_m{};
};
InteractiveReply interactive_sample(interactive::Session&,const interactive::AnalyticSurface&);
class InteractiveWorker final {
 public:
  explicit InteractiveWorker(interactive::Config);
  ~InteractiveWorker();
  InteractiveWorker(const InteractiveWorker&)=delete;
  InteractiveWorker& operator=(const InteractiveWorker&)=delete;
  InteractiveReply call(std::function<InteractiveReply(interactive::Session&)>);
  void close() noexcept;
  static void close_all() noexcept;
 private:
  struct Request {std::function<InteractiveReply(interactive::Session&)> operation;std::promise<InteractiveReply> promise;};
  std::mutex mutex_;std::condition_variable condition_;
  std::deque<Request> pending_;bool closing_{};
  std::jthread thread_;
};
void register_interactive_bridge();
void close_interactive_bridges() noexcept;
}
