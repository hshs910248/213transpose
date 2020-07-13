#!/bin/bash

# $d1 $d2 $d3 $size_of_data_type

PARAMS=(        "2 178125000 2 4"\
        "2 89062500 4 4"\
        "2 44531250 8 4"\
        "2 22265625 16 4"\
        "2 11132812 32 4"\
        "2 5566406 64 4"\
        "2 2783203 128 4"\
        "2 1391601 256 4"\
        "2 695800 512 4"\
        "2 347900 1024 4"\
        "2 173950 2048 4"\
        "2 86975 4096 4"\
        "2 43487 8192 4"\
        "2 21743 16384 4"\
        "2 10871 32768 4"\
        "2 5435 65536 4"\
        "2 2717 131072 4"\
        "2 1358 262144 4"\
        "2 679 524288 4"\
        "2 339 1048576 4"\
        "2 169 2097152 4"\
        "2 84 4194304 4"\
        "2 42 8388608 4"\
        "2 21 16777216 4"\
        "2 10 33554432 4"\
        "2 5 67108864 4"\
        "2 2 134217728 4"\
)


#PARAMS=("2 178125000 2 4"\
#        "31 695800 31 4"\
#		"30 695800 29 4"\
#		"695800 28 30 4"\
#        "178125000 2 2 4"\
#)

if [ ! -d "./testcase" ]; then
    mkdir -p ./testcase
fi

for ((i=0;i<${#PARAMS[@]};++i)) ; do
        if [ $i -le 23 ]; then
            continue
        fi
        
        echo "Case $i"
        echo "./test_213inplace ${PARAMS[$i]} > ./testcase/res_case$i.out"
        ./test_213inplace ${PARAMS[$i]} ./testcase/res_case$i.out
		diff ./testcase/ans_case$i.out ./testcase/res_case$i.out
		rm -f ./testcase/res_case$i.out
done
