#pragma once
#include <array>
#include <cstdint>
#include <string_view>
namespace flight::fdm {
struct OriginalModelFile { const char* path; std::uint64_t bytes; std::string_view sha256; };
inline constexpr std::array<OriginalModelFile, 3> original_model_files{{
  {"aircraft/original-synthetic/original-synthetic.xml", 4691, "e271188986517f459197bb2a4573d5e912a1eeb31e9ad92593ed0ab43424136c"},
  {"engine/original-synthetic-direct.xml", 100, "30c8dbec55a756c71d639aef1cf720decff0ba6730af5ec2062608a08d24d00b"},
  {"engine/original-synthetic-thrust.xml", 561, "547581e279e9b3f383422ddff7991b0ff1cef6f02054bf0a979cd6859d9ef073"},
}};
}
