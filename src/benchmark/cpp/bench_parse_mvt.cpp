#include <vtzero/vector_tile.hpp>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

namespace fs = std::filesystem;

static std::vector<fs::path> list_mvt_paths(const fs::path& dir) {
    std::vector<fs::path> paths;
    for (const auto& entry : fs::directory_iterator(dir)) {
        if (!entry.is_regular_file()) {
            continue;
        }
        const auto& p = entry.path();
        if (p.extension() == ".mvt") {
            paths.push_back(p);
        }
    }
    std::sort(paths.begin(), paths.end());
    return paths;
}

int main(int argc, char** argv) {
    const fs::path dir =
        (argc >= 2) ? argv[1] : "vtzero/test/mvt-fixtures/real-world/bangkok";

    if (!fs::exists(dir) || !fs::is_directory(dir)) {
        std::cerr << "not a directory: " << dir.string() << "\n";
        return 1;
    }

    const std::vector<fs::path> paths = list_mvt_paths(dir);

    std::vector<std::string> datas;
    datas.reserve(paths.size());
    for (const auto& p : paths) {
        std::ifstream in(p, std::ios::binary);
        if (!in) {
            std::cerr << "failed to open: " << p.string() << "\n";
            return 1;
        }
        datas.emplace_back(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    }

    if (datas.empty()) {
        std::cerr << "no .mvt files in " << dir.string() << "\n";
        return 1;
    }

    std::uint64_t checksum = 0;
    std::uint64_t feature_visits = 0;
    const std::size_t iters = 200;

    const auto start = std::chrono::steady_clock::now();
    for (std::size_t i = 0; i < iters; ++i) {
        for (const auto& data : datas) {
            vtzero::vector_tile tile{data};
            checksum += static_cast<std::uint64_t>(tile.count_layers());
            while (auto layer = tile.next_layer()) {
                checksum += static_cast<std::uint64_t>(layer.name().size());
                while (auto feature = layer.next_feature()) {
                    ++feature_visits;
                    checksum += feature.id();
                    checksum += static_cast<std::uint64_t>(feature.num_properties());
                    checksum += static_cast<std::uint64_t>(feature.geometry_type());
                }
            }
        }
    }
    const auto end = std::chrono::steady_clock::now();

    const auto elapsed_ns =
        std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();

    const std::uint64_t features_per_iter = feature_visits / iters;

    std::cout << "C++: dir=" << dir.string() << " tiles=" << datas.size() << " iters=" << iters
              << " elapsed_ns=" << elapsed_ns
              << " per_iter_ns=" << (elapsed_ns / static_cast<long long>(iters))
              << " features_per_iter=" << features_per_iter << " checksum=" << checksum << "\n";
    return 0;
}
