#!/bin/bash
# Check a patch for style errors.
usage="./checkpatch.sh <patch> <tree>"
patch=$1
tree=$2
checkpatch="$tree/tools/checkpatch.pl --no-tree -f"
ignore="ldpd\|babeld"
cwd=${PWD##*/}
dirty=0
stat=0

if [[ -z "$1" || -z "$2" ]]; then
  echo "$usage"
  exit 0
fi

# remove temp directories
rm -rf /tmp/f1 /tmp/f2

# save working tree
if git -C $tree status --porcelain | egrep --silent '^(\?\?|.[DM])'; then
  echo "Detected dirty tree, caching state..."
  dirty=1
  git -C $tree config gc.auto 0;
  td=$(git -C $tree status -z | grep -z "^[ARM]D" | cut -z -d' ' -f2- | tr '\0' '\n')
  INDEX=$(git -C $tree write-tree)
  git -C $tree add -f .
  WORKTREE=$(git -C $tree write-tree)
  echo "Saved index to $INDEX"
  echo "Saved working tree to $WORKTREE"
fi

# double check
if git -C $tree status --porcelain | egrep --silent '^(\?\?|.[DM])'; then
  echo "[!] git working directory must be clean."
  exit 1
fi

git -C $tree reset --hard
git -C $tree apply < $patch
mkdir -p /tmp/f1 /tmp/f2
mod=$(git -C $tree ls-files -m | grep ".*\.[ch]" | grep -v $ignore)
mod+=" $(git -C $tree ls-files --others --exclude-standard | grep '.*\.[ch]' | grep -v $ignore)"
echo $mod
if [ -z "$mod" ]; then
  echo "There doesn't seem to be any changes."
else
  echo "Copying source to temp directory..."
  for file in $mod; do
    echo "$tree/$file --> /tmp/f1/$file"
    cp $tree/$file /tmp/f1/
  done
  git -C $tree reset --hard
  git -C $tree clean -fd
  for file in $mod; do
    if [ -f $tree/$file ]; then
      echo "$tree/$file --> /tmp/f2/$file"
      cp $tree/$file /tmp/f2/
    fi
  done
  echo "Running style checks..."
  for file in /tmp/f1/*; do
    echo "$checkpatch $file > $file _cp"
    $checkpatch $file > "$file"_cp 2> /dev/null
  done
  for file in /tmp/f2/*; do
    echo "$checkpatch $file > $file _cp"
    $checkpatch $file > "$file"_cp 2> /dev/null
  done
  echo "Done."
  for file in /tmp/f1/*_cp; do
    if [ -a /tmp/f2/$(basename $file) ]; then
      result=$(diff $file /tmp/f2/$(basename $file) | grep -A3 "ERROR\|WARNING" | grep -A2 -B2 '/tmp/f1')
    else
      result=$(cat $file | grep -A3 "ERROR\|WARNING" | grep -A2 -B2 '/tmp/f1')
    fi
    if [ "$?" -eq "0" ]; then
      echo "Report for $(basename $file _cp)" 1>&2
      echo "===============================================" 1>&2
      echo "$result" 1>&2
      if echo $result | grep -q "ERROR"; then
        stat=2
      elif [ "$stat" -eq "0" ]; then
        stat=1
      fi
    fi
  done
fi

# restore working tree
if [ $dirty -eq 1 ]; then
  git -C $tree read-tree $WORKTREE;
  git -C $tree checkout-index -af;
  git -C $tree read-tree $INDEX;
  if [ -n "$td" ]; then
    rm $td
  fi
  git -C $tree config --unset gc.auto;
fi

exit $stat
