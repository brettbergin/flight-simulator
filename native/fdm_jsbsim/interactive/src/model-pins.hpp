#pragma once
#include <array>
#include <string_view>
struct FilePin {std::string_view path;std::size_t bytes;std::string_view sha;};
inline constexpr std::array<FilePin,4> file_pins{{
  {"inventory.json",1380,"98b30b5641ce86cc6f0af6298424606aa96a1e4a35ef3e9fcaf377bebb3f00cd"},
  {"aircraft/original-interactive/original-interactive.xml",6151,"0213ab8c1176e5d20b01f980da9cb94913f3e9ad8866838adc7e77bf3130722a"},
  {"engine/original-synthetic-thrust.xml",561,"547581e279e9b3f383422ddff7991b0ff1cef6f02054bf0a979cd6859d9ef073"},
  {"engine/original-synthetic-direct.xml",100,"30c8dbec55a756c71d639aef1cf720decff0ba6730af5ec2062608a08d24d00b"},
}};
