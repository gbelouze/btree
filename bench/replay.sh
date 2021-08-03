export DATA=~/Documents/data
export OUTPUT=~/Documents/output
export C=100_000

cd ~/Documents/irmin
opam switch irmin && eval $(opam env)
rm -rf $DATA/sess2_t1nest_a
MEMTRACE=$OUTPUT/$C-irmin-trace.ctf dune exec -- ./bench/irmin-pack/tree.exe --mode trace $DATA/trace.repr --ncommits-trace $C --keep-stat-trace --path-conversion none  --artefacts $DATA/sess2_t1nest_a -v 2>&1 | tee $OUTPUT/$C-irmin.out
mv small-trace.btree.repr $DATA/$C-trace.btree.repr

cd ~/Documents/btree
opam switch test && eval $(opam env)
MEMTRACE=$OUTPUT/$C-btree-trace.ctf dune exec bench/replay.exe -- -vv $DATA/$C-trace.btree.repr 2>&1 | tee $OUTPUT/$C-btree.out