#!/usr/bin/env python3
"""Build a small test BIOS and test cartridges for the Astrocade simulation
(Z80 machine code). No Bally/Astrocade ROM is needed or included.

test_bios.bin (8 KB): jumps to the cartridge if its first byte is a JP
instruction, otherwise paints the screen with the "no cartridge" colour.

test_cart.bin (4 KB, or 8 KB with --8k): sets the colour registers from
the controls so the simulation can check the path from the Pocket buttons
to the picture, turns a tone on, and copies the knob (pot 1) into the
left-hand colours:

    right-hand side      nothing pressed  IDLE (or MARK, see below)
                         trigger          TRIG
                         joystick up      UP
                         keypad 1         KEY1
                         keypad 5         KEY5
                         keypad =         EQ
    left-hand side       the knob value as a colour

The 8 KB version has 0x5A at 0x3FFF and shows MARK instead of IDLE when it
finds it there; after loading the 8 KB cartridge and then the 4 KB one,
the idle colour must be IDLE again (bytes past the end of a file read 0).

usage: make_test_roms.py <outdir>
"""
import os
import sys

IDLE, MARK, TRIG, UP, KEY1, KEY5, EQ, NOCART = 0x33, 0x8B, 0xD7, 0x1F, 0x6E, 0xF3, 0xA5, 0x07


class Z80:
    def __init__(self, base):
        self.base = base
        self.code = {}
        self.pc = base
        self.labels = {}
        self.fix = []

    def label(self, n):
        self.labels[n] = self.pc

    def emit(self, *bs):
        for b in bs:
            self.code[self.pc] = b & 0xFF
            self.pc += 1

    def ld_a(self, n):     self.emit(0x3E, n)
    def ld_sp(self, nn):   self.emit(0x31, nn & 0xFF, nn >> 8)
    def ld_a_mem(self, nn): self.emit(0x3A, nn & 0xFF, nn >> 8)
    def out(self, p):      self.emit(0xD3, p)
    def inp(self, p):      self.emit(0xDB, p)
    def cp(self, n):       self.emit(0xFE, n)
    def bit(self, b):      self.emit(0xCB, 0x47 + 8 * b)   # BIT b,A
    def di(self):          self.emit(0xF3)

    def jp(self, label, cond=None):   # cond: None, 'z', 'nz'
        op = {None: 0xC3, 'z': 0xCA, 'nz': 0xC2}[cond]
        self.fix.append(('abs', self.pc + 1, label))
        self.emit(op, 0, 0)

    def jr(self, label, cond=None):
        op = {None: 0x18, 'z': 0x28, 'nz': 0x20}[cond]
        self.fix.append(('rel', self.pc + 1, label))
        self.emit(op, 0)

    def build(self, size):
        for kind, at, label in self.fix:
            t = self.labels[label] if isinstance(label, str) else label
            if kind == 'abs':
                self.code[at] = t & 0xFF
                self.code[at + 1] = t >> 8
            else:
                d = t - (at + 1)
                assert -128 <= d <= 127, (label, d)
                self.code[at] = d & 0xFF
        out = bytearray(size)
        for a, b in self.code.items():
            out[a - self.base] = b
        return out


def set_colours(z, ports):
    for p in ports:
        z.out(p)


def bios():
    z = Z80(0x0000)
    z.di()
    z.ld_sp(0x4F00)
    z.ld_a_mem(0x2000)
    z.cp(0xC3)                     # cartridge starts with JP?
    z.jp(0x2000, 'z')
    z.ld_a(NOCART)
    set_colours(z, range(8))
    z.label('hang')
    z.jr('hang')
    return z.build(0x2000)


def cart(size):
    z = Z80(0x2000)
    z.jp('start')
    z.label('start')
    z.ld_a(0x40); z.out(0x10)      # sound: master oscillator
    z.ld_a(0x20); z.out(0x11)      # tone A
    z.ld_a(0x0F); z.out(0x16)      # tone A volume
    z.ld_a(0x14); z.out(0x09)      # colour boundary in the middle
    z.label('loop')
    z.inp(0x1C)                    # pot 1 (knob) -> left-hand colours
    set_colours(z, range(4, 8))
    checks = [
        (0x10, 4, TRIG),           # trigger
        (0x10, 0, UP),             # joystick up
        (0x17, 4, KEY1),           # keypad 1
        (0x16, 3, KEY5),           # keypad 5
        (0x14, 5, EQ),             # keypad =
    ]
    for i, (port, b, colour) in enumerate(checks):
        z.inp(port)
        z.bit(b)
        z.jr(f'n{i}', 'z')
        z.ld_a(colour)
        z.jp('store')
        z.label(f'n{i}')
    z.ld_a_mem(0x3FFF)
    z.cp(0x5A)
    z.jr('idle', 'nz')
    z.ld_a(MARK)
    z.jp('store')
    z.label('idle')
    z.ld_a(IDLE)
    z.label('store')
    set_colours(z, range(0, 4))
    z.jp('loop')
    data = z.build(size)
    if size == 0x2000:
        data[0x1FFF] = 0x5A
    return data


PASS, STACKFAIL, RAMFAIL, INTFAIL = 0x5B, 0xC6, 0x8E, 0x2C


def full_cart():
    """Exercises what a real BIOS and game use and the simple cartridge does
    not: the stack (CALL/RET), the console RAM, IM 2 interrupts from the
    screen interrupt line, and the screen RAM. Shows PASS in colour 0 when
    everything works, otherwise the colour of the first thing that failed."""
    z = Z80(0x2000)
    z.jp('start')
    z.pc = 0x2040                  # IM 2 vector table entry (I=0x20, vector 0x40)
    z.fix.append(('abs', 0x2040, 'handler')); z.emit(0, 0)
    z.pc = 0x2050
    z.label('start')
    z.ld_sp(0x4F00)
    z.ld_a(0); z.emit(0x32, 0x80, 0x4F)          # LD (4F80h),A  interrupt counter
    z.ld_a(0); z.emit(0x32, 0x81, 0x4F)          # LD (4F81h),A  stack flag
    z.fix.append(('abs', z.pc + 1, 'sub')); z.emit(0xCD, 0, 0)   # CALL sub
    z.ld_a(0x20); z.emit(0xED, 0x47)             # LD I,A
    z.emit(0xED, 0x5E)                           # IM 2
    z.ld_a(0x40); z.out(0x0D)                    # interrupt vector
    z.ld_a(0x64); z.out(0x0F)                    # interrupt line
    z.ld_a(0x08); z.out(0x0E)                    # screen interrupt on
    z.emit(0xFB)                                 # EI
    z.ld_a(0xC8); z.out(0x0A)                    # vertical blank line: show screen RAM
    z.ld_a(0x07); z.out(0x01); z.out(0x05)       # colour 1 white
    z.emit(0x21, 0x00, 0x40)                     # LD HL,4000h
    z.emit(0x06, 0x00)                           # LD B,0
    z.label('fill')
    z.emit(0x36, 0x55)                           # LD (HL),55h
    z.emit(0x23)                                 # INC HL
    z.fix.append(('rel', z.pc + 1, 'fill')); z.emit(0x10, 0)     # DJNZ fill
    z.label('main')
    z.emit(0x3A, 0x81, 0x4F)                     # LD A,(4F81h)
    z.cp(1)
    z.jr('ok1', 'z')
    z.ld_a(STACKFAIL); z.jp('show')
    z.label('ok1')
    z.ld_a(0xA5); z.emit(0x32, 0x00, 0x48)       # LD (4800h),A
    z.ld_a(0x00)
    z.emit(0x3A, 0x00, 0x48)                     # LD A,(4800h)
    z.cp(0xA5)
    z.jr('ok2', 'z')
    z.ld_a(RAMFAIL); z.jp('show')
    z.label('ok2')
    z.emit(0x3A, 0x80, 0x4F)                     # LD A,(4F80h)
    z.cp(0)
    z.jr('ok3', 'nz')
    z.ld_a(INTFAIL); z.jp('show')
    z.label('ok3')
    z.ld_a(PASS)
    z.label('show')
    z.out(0x00); z.out(0x04)
    z.jp('main')
    z.label('sub')
    z.ld_a(1); z.emit(0x32, 0x81, 0x4F)          # LD (4F81h),A
    z.emit(0xC9)                                 # RET
    z.label('handler')
    z.emit(0xF5)                                 # PUSH AF
    z.emit(0x3A, 0x80, 0x4F)                     # LD A,(4F80h)
    z.emit(0x3C)                                 # INC A
    z.emit(0x32, 0x80, 0x4F)                     # LD (4F80h),A
    z.emit(0xF1)                                 # POP AF
    z.emit(0xFB)                                 # EI
    z.emit(0xED, 0x4D)                           # RETI
    return z.build(0x1000)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'roms'
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, 'test_bios.bin'), 'wb').write(bios())
    open(os.path.join(out, 'test_cart.bin'), 'wb').write(cart(0x1000))
    open(os.path.join(out, 'test_cart8k.bin'), 'wb').write(cart(0x2000))
    open(os.path.join(out, 'test_full.bin'), 'wb').write(full_cart())
    print(f'{out}: test_bios.bin, test_cart.bin (4 KB), test_cart8k.bin (8 KB), test_full.bin')


if __name__ == '__main__':
    main()
