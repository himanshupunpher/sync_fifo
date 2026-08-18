# sync_fifo

A parameterizable synchronous FIFO written in Verilog, and used to add
read/write decoupling to a companion
[UART TX/RX core](https://github.com/himanshupunpher/uart-tx-rx).

---

## What is a FIFO, and why use one

A FIFO (First In, First Out) buffer sits between a producer and a
consumer that run at different, uncorrelated rates, so neither side
has to wait on the other's exact timing.

Concretely, for a UART:

- **TX side:** without a FIFO, the CPU has to poll `tx_busy` and wait
  for each byte to finish sending before writing the next one. With a
  FIFO, the CPU can write several bytes back-to-back, and `tx_fsm`
  drains them one at a time in the background at its own pace.
- **RX side:** incoming bytes arrive whenever the far end sends them,
  entirely outside the CPU's control. If the CPU doesn't read
  `rx_data` before the next byte finishes arriving, the previous byte
  is silently lost — an *overrun*. A FIFO buys the CPU several bytes
  of slack before that happens.

The `full` flag protects the writer from overflowing the buffer; the
`empty` flag protects the reader from reading invalid/stale data.

---

## Repo structure

```
sync-fifo/
├── README.md
├── LICENSE
├── src/
│   └── sync_fifo.v          # the FIFO module
└── tb/
    └── sync_fifo_tb.v        # self-checking testbench
```

---

## Module: `sync_fifo`

### Ports

| Port       | Direction | Width | Description                        |
|------------|-----------|-------|-------------------------------------|
| `clk`      | input     | 1     | Clock                               |
| `rst`      | input     | 1     | Synchronous, active-high reset      |
| `wr_en`    | input     | 1     | Write enable                        |
| `data_in`  | input     | 8     | Data to write                       |
| `rd_en`    | input     | 1     | Read enable                         |
| `data_out` | output    | 8     | Data read out                       |
| `full`     | output    | 1     | High when FIFO has no room left     |
| `empty`    | output    | 1     | High when FIFO has no data to read  |

### Parameters

Set via `localparam` inside the module — edit directly to change size:

- `DEPTH` — number of entries (default 8)
- `WIDTH` — bits per entry (default 8)

### How it works internally

- `mem` is a `DEPTH`-entry register array, `WIDTH` bits wide —
  `DEPTH` separate registers, each individually addressable.
- `wr_ptr` and `rd_ptr` are each **one bit wider** than needed to
  address `mem` (e.g. 4 bits for a depth-8 FIFO, though only the lower
  3 bits are used as the memory address). The extra MSB tracks how
  many times each pointer has wrapped around the array.
- **`empty`** = `wr_ptr == rd_ptr` (fully equal, including the extra
  bit) — the read pointer has caught up to the write pointer exactly,
  meaning zero bytes are currently stored.
- **`full`** = lower address bits equal, but the extra MSBs differ —
  the write pointer has lapped the read pointer exactly once, meaning
  all `DEPTH` slots hold unread data.
- Write and read logic are independent `if` blocks (not
  `if`/`else if`), so a simultaneous write and read on the same clock
  cycle both succeed when the FIFO is neither full nor empty — the
  FIFO doesn't force the two sides to take turns.
- Writes while `full` and reads while `empty` are silently ignored —
  no overflow/underflow corruption.

### Usage

```verilog
sync_fifo u_fifo (
    .clk(clk),
    .rst(rst),
    .wr_en(wr_en),
    .data_in(data_in),
    .rd_en(rd_en),
    .data_out(data_out),
    .full(full),
    .empty(empty)
);
```

Gate writes on `!full` and reads on `!empty` from the driving logic as
well, even though the module protects itself internally — this keeps
dropped writes/reads from becoming silent, unintended behavior in your
larger design.

---

## Testing

`tb/sync_fifo_tb.v` is a self-checking testbench covering:

- Reset behavior (`empty` high, `full` low on startup)
- Basic single write, single read
- Filling to full (8 writes) and confirming the `full` flag
- Overflow protection — a write while full is ignored, no corruption
- Draining to empty (8 reads) and confirming correct FIFO ordering
  (not just that the flags behave, but that data comes out in the
  same order it went in)
- Underflow protection — a read while empty is ignored
- Simultaneous write and read on the same clock cycle

### Run with Icarus Verilog

```bash
iverilog -o fifo_sim src/sync_fifo.v tb/sync_fifo_tb.v
vvp fifo_sim
```

Every check prints `PASS` or `FAIL` to the console. No `FAIL` lines
means the module is behaving correctly.

## Using this with a UART core

This FIFO was built to decouple a UART's baud-rate-paced TX/RX from
CPU-side timing. Two independent instances are used — one buffers
bytes waiting to be transmitted, the other buffers received bytes
waiting to be read by the CPU. Both instances share the same module
definition but have entirely separate memory and pointers; writing to
one has no effect on the other.

```verilog
module uart_top (
    input  clk,
    input  rst,
    input  rx_line,
    output tx_line,

    // CPU with TX
    input        cpu_wr_en,
    input  [7:0] cpu_data_in,
    output       tx_fifo_full,

    // CPU with RX interface
    input        cpu_rd_en,
    output [7:0] cpu_data_out,
    output       rx_fifo_empty
);

    // ---------------- TX path ----------------
    wire tx_fifo_empty;
    wire [7:0] tx_byte_to_send;
    wire tx_fifo_rd_en;
    wire tx_busy;

    sync_fifo u_tx_fifo (
        .clk(clk), .rst(rst),
        .wr_en(cpu_wr_en), .data_in(cpu_data_in),
        .rd_en(tx_fifo_rd_en), .data_out(tx_byte_to_send),
        .full(tx_fifo_full), .empty(tx_fifo_empty)
    );

    // tx_fsm pulls the next byte whenever it's idle and the FIFO
    // has something waiting
    assign tx_fifo_rd_en = !tx_busy && !tx_fifo_empty;

    uart_tx u_uart_tx (
        .clk(clk), .rst(rst),
        .tx_start(tx_fifo_rd_en),
        .tx_data(tx_byte_to_send),
        .tx_busy(tx_busy),
        .tx_line(tx_line)
        // match to actual uart_tx port names
    );

    // ---------------- RX path ----------------
    wire [7:0] rx_data;
    wire rx_done;
    wire rx_fifo_full;

    uart_rx u_uart_rx (
        .clk(clk), .rst(rst),
        .rx_line(rx_line),
        .rx_data(rx_data),
        .rx_done(rx_done)
        // match to actual uart_rx port names
    );

    sync_fifo u_rx_fifo (
        .clk(clk), .rst(rst),
        .wr_en(rx_done), .data_in(rx_data),
        .rd_en(cpu_rd_en), .data_out(cpu_data_out),
        .full(rx_fifo_full), .empty(rx_fifo_empty)
    );

endmodule
```

**Key points:**

- `tx_fifo_rd_en` is derived combinationally from
  `!tx_busy && !tx_fifo_empty` — `tx_fsm` doesn't need to know a FIFO
  exists, it just receives `tx_start` pulsed whenever a byte is ready.
- `rx_done` connects directly to the RX FIFO's `wr_en` — the pulse
  itself is the write enable, no extra logic needed.
- If `rx_fifo_full` is high when `rx_done` pulses, that byte is
  silently dropped (overrun). This is a known limitation of the
  minimal integration above; an `rx_overrun` flag
  (`rx_done && rx_fifo_full`) can be added later if overrun detection
  becomes necessary.
  
### GTKwave output

![GTKWave simulation waveform](docs/waveform.png)

### What to test at the integration level

The FIFO's own correctness is already covered by `tb/sync_fifo_tb.v`
above. When testing a `uart_top`-style wrapper, focus on the
integration points instead of re-testing FIFO internals:

- CPU writes several bytes rapidly to `cpu_data_in` before `tx_fsm`
  finishes sending the first — confirm no data is lost and bytes go
  out on the wire in the correct order.
- Drive `rx_line` with several back-to-back bytes faster than the CPU
  drains `cpu_data_out` — confirm correct buffering up to FIFO depth,
  and the expected drop behavior beyond it.

---
