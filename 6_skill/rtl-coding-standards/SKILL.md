---
name: rtl-coding-standards
description: Enforce the project's strict Verilog/SystemVerilog RTL coding standards when creating, modifying, reviewing, or formatting .v, .sv, or .vh files, including modules, testbenches, FSMs, and RTL instantiations.
---

# RTL Coding Standards

> 本文件为 `D:\VitA\12_skills\rtl-coding-standards\SKILL.md` 的本地副本，适用于本工程 `2_fpga/` 下的 Verilog/SystemVerilog。可在此继续补充 Logos-2/PDS 的项目约束，不修改 ViTA 源文件。

Apply this skill to every Verilog/SystemVerilog source change in this project. Treat the rules below as mandatory unless the user explicitly overrides them.

## Mandatory top-level rules

1. Keep one statement or operation per line. Never place multiple statements, assignments, declarations, or control operations on one line.
2. Implement every FSM with the strict three-block structure described below. Use exactly `state` for the registered current state and `next_state` for the combinational next state.
3. Put the standardized file header on line 1 of every newly created `.v`, `.sv`, or `.vh` file. For an existing RTL file, append a revision entry in its existing header; do not erase prior history.

## Required file header

Use this comment block for new source files, replacing placeholders with project-specific values:

```verilog
/************************************************************************
 * File Name       : module_name.v
 * Developer       : LSL
 * Date            : YYYY-MM-DD
 * Project Name    : RK3568_MES2L100H / Logos-2 distortion correction
 * Module Name     : [current module name]
 * Description     : [interfaces, protocol, and core function]
 * Dependencies    : [submodules or header files, or None]
 * Revision History:
 *   - V1.0 (YYYY-MM-DD) by LSL : Initial release
 ************************************************************************/
```

For an existing file, add a new entry such as:

```verilog
 *   - V1.1 (YYYY-MM-DD) by LSL : [concise change description]
```

## FSM implementation

Use `localparam` or SystemVerilog `enum` for state values. Do not hard-code state literals throughout the logic. Define the current and next state with the exact names `state` and `next_state`.

### Block 1: state register

This block only registers the next state and handles reset:

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end
```

### Block 2: next-state logic

Use pure combinational logic. Set a default hold value first and include a `default` case:

```verilog
always @(*) begin
    next_state = state;

    case (state)
        IDLE: begin
            if (start_en) begin
                next_state = START;
            end
        end
        START: begin
            if (done_flag) begin
                next_state = IDLE;
            end
        end
        default: begin
            next_state = IDLE;
        end
    endcase
end
```

### Block 3: registered output logic

Keep FSM outputs in a separate sequential block to avoid glitches. Reset every registered output explicitly:

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_valid_o <= 1'b0;
    end else begin
        if (next_state == START) begin
            out_valid_o <= 1'b1;
        end else begin
            out_valid_o <= 1'b0;
        end
    end
end
```

Do not combine state register, next-state calculation, and registered output logic into one block. If a module has no FSM, do not invent one solely to satisfy this section.

## RTL naming and interface rules

- Keep the module name and file name identical.
- Suffix input ports with `_i` and output ports with `_o`.
- Suffix active-low signals with `_n`, especially resets such as `rst_n`.
- Use descriptive names for clocks, resets, enables, valid/ready signals, addresses, data, and state transitions.
- Instantiate modules with named port connections only. Never use positional connections:

```verilog
submodule_name u_submodule_name (
    .clk_i(clk_i),
    .rst_n(rst_n),
    .data_i(data_i),
    .valid_o(valid_o)
);
```

## Width, constants, and parameterization

- Replace magic numbers with `parameter` or `localparam` declarations.
- Declare all widths, depths, loop limits, state encodings, timeout values, and protocol constants explicitly.
- Give every numeric literal an explicit width and base, for example `4'd0`, `8'hFF`, or `1'b0`.
- Keep signedness explicit where arithmetic crosses module or pipeline boundaries.
- Check truncation, extension, rounding, saturation, and accumulator widths before finalizing arithmetic RTL.

## Combinational and sequential logic

- Use `always @(*)` for combinational logic in the project's required FSM pattern.
- Give combinational outputs defaults before conditional or case logic.
- Complete every `if` with the required `else` behavior when a latch could otherwise be inferred.
- Include a `default` branch in every combinational `case` statement.
- Use nonblocking assignments in clocked blocks and blocking assignments in combinational blocks.
- Do not mix unrelated sequential responsibilities in one clocked block when separation improves reviewability.
- Preserve reset polarity and reset values consistently across the module hierarchy.

## Editing and review workflow

1. Read the target file, its direct dependencies, and relevant testbench before changing RTL.
2. Preserve existing interfaces and timing semantics unless the user requests an interface change.
3. Add or update the file header and revision history.
4. Apply the naming, width, constant, FSM, latch, and instantiation rules above.
5. Inspect the diff for same-line multiple statements, missing header text, magic numbers, positional ports, incomplete combinational assignments, and FSM blocks that are not three-part.
6. Run the project's available syntax/lint or simulation check appropriate to the changed module. Preserve the complete raw transcript or console output in the project's run record.
7. Report any pre-existing violations separately from violations introduced by the change.

## Final compliance checklist

- [ ] New RTL file starts with the required header on line 1.
- [ ] Existing RTL header has a new revision entry when modified.
- [ ] No line contains multiple statements or operations.
- [ ] Every FSM uses `state`, `next_state`, and three separate blocks.
- [ ] Every combinational block has defaults and complete case coverage.
- [ ] Constants and widths are parameterized and explicitly sized.
- [ ] Ports use `_i`, `_o`, and `_n` conventions where applicable.
- [ ] All module instances use named port connections.
- [ ] Relevant syntax, lint, or simulation evidence is preserved.
