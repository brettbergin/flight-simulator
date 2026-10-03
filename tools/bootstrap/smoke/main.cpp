#include <FGFDMExec.h>
#include <sqlite3.h>
#include <array>
#include <cmath>
#include <iostream>
#include <memory>
#include <numeric>
#include <span>
#include <stdexcept>
#include <string>
static_assert(__cplusplus >= 202002L, "Project code must compile as C++20.");
namespace {
void require(bool result, const char* message) {
    if (!result) throw std::runtime_error(message);
}
void execute(sqlite3* db, const char* statement) {
    char* error = nullptr;
    const int status = sqlite3_exec(db, statement, nullptr, nullptr, &error);
    const std::string detail = error ? error : "SQLite execution failure";
    sqlite3_free(error);
    if (status != SQLITE_OK) throw std::runtime_error(detail);
}
}
int main() {
    try {
        const std::array inputs{1, 2, 3};
        const std::span<const int> values(inputs);
        require(std::accumulate(values.begin(), values.end(), 0) == 6, "C++20 span probe failed");
        JSBSim::FGFDMExec executive;
        executive.Setdt(1.0 / 120.0);
        require(std::abs(executive.GetDeltaT() - 1.0 / 120.0) < 1e-15, "JSBSim DLL interface mismatch");
        sqlite3* raw = nullptr;
        require(sqlite3_open(":memory:", &raw) == SQLITE_OK, "SQLite open failed");
        const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> db(raw, sqlite3_close);
        require(sqlite3_libversion_number() == 3053004, "SQLite version differs from lock");
        execute(db.get(), "CREATE TABLE probes(value INTEGER NOT NULL); BEGIN; INSERT INTO probes VALUES(7); COMMIT;");
        execute(db.get(), "BEGIN; INSERT INTO probes VALUES(99); ROLLBACK;");
        sqlite3_stmt* raw_statement = nullptr;
        require(sqlite3_prepare_v2(db.get(), "SELECT count(*),sum(value) FROM probes;", -1, &raw_statement, nullptr) == SQLITE_OK, "SQLite query failed");
        const std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement(raw_statement, sqlite3_finalize);
        require(sqlite3_step(statement.get()) == SQLITE_ROW, "SQLite row missing");
        require(sqlite3_column_int(statement.get(), 0) == 1 && sqlite3_column_int(statement.get(), 1) == 7, "SQLite transaction/rollback mismatch");
        std::cout << "C++20 span: PASS; dynamic JSBSim 1.3.1 dt: " << executive.GetDeltaT()
                  << "; SQLite " << sqlite3_libversion() << " commit/rollback: PASS\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
