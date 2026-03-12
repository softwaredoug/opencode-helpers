def hello(name):
    return f"hello world {name}"


def main():
    import sys

    if len(sys.argv) < 2:
        raise SystemExit("Usage: python3 hello.py <name>")

    print(hello(sys.argv[1]))


if __name__ == "__main__":
    main()
