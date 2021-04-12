#include <iostream>

extern "C" {
    int fact(int);
}

int main() {
    std::cout << fact(10) << std::endl;
}
