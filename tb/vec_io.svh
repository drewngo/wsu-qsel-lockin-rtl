// Copyright (c) 2026 Andrew Ngo
// Author: Andrew Ngo, Quantum Science and Engineering Lab
//
// Test-vector helpers, `include'd inside each testbench module.
// Vector files come from model/gen_vectors.py: one sample per line,
// space-separated decimal integers, '#' comment lines. Pass the vector
// directory with +VEC=<dir>, or let vec_open look for <repo>/vectors from the
// usual run folders (tb/build/<test>/ or the Vivado project's xsim folder).

int errors = 0;
int checks = 0;

function automatic int vec_open(string name);
  string dirs[$];
  string dir;
  int fd;
  if ($value$plusargs("VEC=%s", dir)) dirs.push_back(dir);
  dirs.push_back("../../../vectors");                  // tb/build/<test>/
  dirs.push_back("../../../../../../vectors");         // vivado/project/<name>.sim/<set>/behav/xsim/
  foreach (dirs[i]) begin
    fd = $fopen({dirs[i], "/", name}, "r");
    if (fd != 0) return fd;
  end
  $fatal(1, "cannot open %s in any of %p (run model/gen_vectors.py)", name, dirs);
  return 0;
endfunction

// Next data line, skipping comments and blank lines. Returns 0 at end of file.
function automatic int vec_next(int fd, output string line);
  string s;
  while ($fgets(s, fd)) begin
    if (s.len() > 0 && s[0] != "#" && s[0] != "\n" && s[0] != "\r") begin
      line = s;
      return 1;
    end
  end
  return 0;
endfunction

// Compare one value; print the first few mismatches.
function automatic void check(string what, longint got, longint exp, int idx);
  checks++;
  if (got !== exp) begin
    errors++;
    if (errors <= 10) $display("MISMATCH %s[%0d]: rtl=%0d model=%0d", what, idx, got, exp);
  end
endfunction

function automatic void report(string name);
  if (errors == 0 && checks > 0) $display("TEST PASSED: %s, %0d checks", name, checks);
  else $display("TEST FAILED: %s, %0d errors in %0d checks", name, errors, checks);
endfunction
