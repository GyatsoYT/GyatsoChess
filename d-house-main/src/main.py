from multiprocessing import freeze_support
from uci import uci_loop

def main():
    freeze_support()
    uci_loop()

if __name__ == '__main__':    
    main()
