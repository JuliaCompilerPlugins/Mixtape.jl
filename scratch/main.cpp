#include <iostream>

extern "C" {
    int factorial(int);
}

int main() {
    std::cout << factorial(10) << std::endl;
}
