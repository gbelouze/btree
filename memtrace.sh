export SYMBOL="@@"
export DATA=~/Documents/data
export OUTPUT=~/Documents/output
export TRACE=$DATA/400M-trace.repr
export C=100_000

cd ~/Documents/irmin
opam switch irmin && eval $(opam env)

git checkout master
rm -rf $DATA/sess2_t1nest_a
MEMTRACE=$OUTPUT/$C-irmin#master-trace$SYMBOL.ctf dune exec -- ./bench/irmin-pack/tree.exe --mode trace $TRACE --ncommits-trace $C --keep-stat-trace --path-conversion none  --artefacts $DATA/sess2_t1nest_a -v 2>&1 | tee $OUTPUT/$C-irmin#index$SYMBOL.out

git checkout btree
rm -rf $DATA/sess2_t1nest_a
MEMTRACE=$OUTPUT/$C-irmin#btree-trace$SYMBOL.ctf dune exec -- ./bench/irmin-pack/tree.exe --mode trace $TRACE --ncommits-trace $C --keep-stat-trace --path-conversion none  --artefacts $DATA/sess2_t1nest_a -v 2>&1 | tee $OUTPUT/$C-irmin#btree$SYMBOL.out

cd ~/Documents/btree
opam switch test && eval $(opam env)
MEMTRACE=$OUTPUT/$C-btree-trace$SYMBOL.ctf dune exec bench/replay.exe -- -vv $DATA/100M-trace.btree.repr 2>&1 | tee $OUTPUT/$C-btree$SYMBOL.out