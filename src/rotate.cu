#include "rotate.h"
#include "util.h"
#include "equations.h"
#include "smem.h"
#include <vector>
#include <algorithm>

namespace inplace {
namespace detail {

__device__ __forceinline__
unsigned int ctz(unsigned int x) {
    return __ffs(x) - 1;
}

__device__ __forceinline__
unsigned int gcd(unsigned int x, unsigned int y) {
    if (x == 0) return y;
    if (y == 0) return x;
    unsigned int cf2 = ctz(x | y);
    x >>= ctz(x);
    while (true) {
        y >>= ctz(y);
        if (x == y) break;
        if (x > y) {
            unsigned int t = x; x = y; y = t;
        }
        if (x == 1) break;
        y -= x;
    }
    return x << cf2;
}

/*
template<typename F, typename T>
__global__ void coarse(F fn, int d3, int d2, int d1, int master, T* d) {
	size_t d1d2 = (size_t)d1 * (size_t)d2;
	int col = threadIdx.x + master;
	if (col < d1) {
		int rotation_amount = d2 - fn(master);
		if (rotation_amount > 0) {
			int len = d2 / gridDim.x;
			size_t k = blockIdx.x / d3;
			size_t offset = k * d1d2;
			int src = blockIdx.x % d3;
			int src_tmp = d[offset + src * d1 + col];
			int dest = (src + rotation_amount) % d2;
			for (int i = 0; i < len; i++) {
				int dest_tmp = d[offset + dest * d1 + col];
				d[offset + dest * d1 + col] = src_tmp;
				src = dest;
				dest = (src + rotation_amount) % d2;
				src_tmp = dest_tmp;
			}
		}
	}
}

template<typename F, typename T>
void coarse_launch(F fn, int d3, int d2, int d1, T* data) {
	int n_threads = 32;
	int num_blocks_d1 = div_up(d1, 32);
	for (int i = 0; i < num_blocks_d1; i++) {
		int master = i * 32;
		int rotation_amount = d2 - fn(master);
		if (rotation_amount > 0) {
			int num_cycle = (rotation_amount == d2)? 0 : std::__gcd(rotation_amount, d2);
			int n_blocks = num_cycle * d3;

			coarse<<<n_blocks, n_threads>>>(fn, d3, d2, d1, master, data);
		}
	}
	//coarse<<<grid_dim, n_threads>>>(fn, d3, d2, d1, data);
}
*/

template<typename F, typename T>
__global__ void coarse(F fn, int d3, int d2, int d1, int master, int num_cycle, int len, T* d) {
	int col = threadIdx.x + master;
	if (col < d1) {
		int rotation_amount = d2 - fn(master);
		size_t d1d2 = (size_t)d1 * (size_t)d2;
		//size_t cycled3 = (size_t)num_cycle * (size_t)d3;
		//for (size_t srck = blockIdx.x; srck < cycled3; srck += gridDim.x) {
			size_t k = blockIdx.x / num_cycle;
			size_t offset = k * d1d2;
			
			int src = blockIdx.x % num_cycle;
			int src_tmp = d[offset + src * d1 + col];
			int dest = (src + rotation_amount) % d2;
			for (int i = 0; i < len; i++) {
				int dest_tmp = d[offset + dest * d1 + col];
				d[offset + dest * d1 + col] = src_tmp;
				src = dest;
				dest = (src + rotation_amount) % d2;
				src_tmp = dest_tmp;
			}
		//}
	}
}

template<typename F, typename T>
void coarse_launch(F fn, int d3, int d2, int d1, T* data) {
	int num_blocks_d1 = div_up(d1, 32);
	for (int i = 0; i < num_blocks_d1; i++) {
		int master = i * 32;
		int n_threads = 32;
		int rotation_amount = d2 - fn(master);
		int num_cycle = (rotation_amount == d2)? 0 : std::__gcd(rotation_amount, d2);
		if (num_cycle > 0) {
			//int n_blocks = min(num_cycle * d3, get_num_block(coarse<F, T>, n_threads, 0));
			int n_blocks = num_cycle * d3;
			printf("num_cycle = %d\n", num_cycle);
			printf("n_blocks = %d\n", n_blocks);
			coarse<<<n_blocks, n_threads>>>(fn, d3, d2, d1, master, num_cycle, d2 / num_cycle, data);
		}
	}
	//coarse<<<grid_dim, n_threads>>>(fn, d3, d2, d1, data);
}

/*template<typename F, typename T>
__global__ void coarse(F fn, int d3, int d2, int d1, T* d, int* num_cycle) {
	int warp_id = threadIdx.x;
	size_t d1d2 = (size_t)d1 * (size_t)d2;
	int col = threadIdx.x + blockIdx.y * blockDim.x;
	if (col < d1) {
		int rotation_amount = d2 - fn(fn.master(col, warp_id, 32));
		if (rotation_amount > 0) {
			//int c = gcd(rotation_amount, d2);
			int c = num_cycle[blockIdx.y];
			int len = d2 / c;
			for (size_t k = blockIdx.x; k < d3; k += gridDim.x) {
				size_t offset = k * d1d2;
				for (int b = 0; b < c; b++) {
					int src = b;
					int src_tmp = d[offset + src * d1 + col];
					int dest = (src + rotation_amount) % d2;
					for (int i = 0; i < len; i++) {
						int dest_tmp = d[offset + dest * d1 + col];
						d[offset + dest * d1 + col] = src_tmp;
						src = dest;
						dest = (src + rotation_amount) % d2;
						src_tmp = dest_tmp;
					}
				}
			}
		}
	}
}*/

/*template<typename F, typename T>
__global__ void coarse_col_rotate(F fn, int d3, reduced_divisor d2, int d1, T* d) {
    __shared__ T smem[32 * 2];
    int warp_id = threadIdx.x & 0x1f;
    
    //size_t l = chunk_left(blockIdx.x, gridDim.x, d3);
    //size_t r = chunk_right(blockIdx.x, gridDim.x, d3);
    size_t d1d2 = (size_t)d1 * (size_t)d2.get();
    for (int k = blockIdx.x; k < d3; k += gridDim.x) {
    //for (int k = l; k < r; k++) {
        size_t offset = k * d1d2;
        for (int col = threadIdx.x + blockIdx.y * blockDim.x; col < d1; col += gridDim.y * blockDim.x) {
            int rotation_amount = fn(fn.master(col, warp_id, 32));
            __syncthreads();
            if (rotation_amount > 0) {
                row_major_index rm(d2, d1);
                int c = gcd(rotation_amount, d2.get());
                int l = d2.get() / c;
                size_t inc = d2.get() - rotation_amount;
                int smem_write_idx = threadIdx.y * 32 + threadIdx.x;
                int max_col = (l > 2) ? 1 : l - 1;
                int smem_read_col = (threadIdx.y == 0) ? max_col : (threadIdx.y - 1);
                int smem_read_idx = smem_read_col * 32 + threadIdx.x;
                
                for(int b = 0; b < c; b++) {
                    size_t x = threadIdx.y;
                    size_t pos = ((size_t)b + x * inc) % (size_t)d2.get();   // (b + x * inc) % d2
                    //int pos = d2.mod(b + x * inc);   // (b + x * inc) % d2
                    smem[smem_write_idx] = d[offset + rm(pos, col)];
                    __syncthreads();
                    T prior = smem[smem_read_idx];
                    if (x < l) d[offset + rm(pos, col)] = prior;
                    __syncthreads();
                    int n_rounds = l / 2;
                    for(int i = 1; i < n_rounds; i++) {
                        x += blockDim.y;
                        size_t pos = ((size_t)b + x * inc) % (size_t)d2.get();   // (b + x * inc) % d2
                        //int pos = d2.mod(b + x * inc);            
                        if (x < l) smem[smem_write_idx] = d[offset + rm(pos, col)];
                        __syncthreads();
                        T incoming = smem[smem_read_idx];
                        T outgoing = (threadIdx.y == 0) ? prior : incoming;
                        if (x < l) d[offset + rm(pos, col)] = outgoing;
                        prior = incoming;
                        __syncthreads();
                    }
                    //Last round/cleanup
                    x += blockDim.y;
                    pos = ((size_t)b + x * inc) % (size_t)d2.get();
                    //pos = d2.mod(b + x * inc);
                    if (x <= l) smem[smem_write_idx] = d[offset + rm(pos, col)];
                    __syncthreads();
                    int remainder_length = (l % 2);
                    int fin_smem_read_col = (threadIdx.y == 0) ? remainder_length : threadIdx.y - 1;
                    int fin_smem_read_idx = fin_smem_read_col * 32 + threadIdx.x;
                    T incoming = smem[fin_smem_read_idx];
                    T outgoing = (threadIdx.y == 0) ? prior : incoming;
                    if (x <= l) d[offset + rm(pos, col)] = outgoing;
                    
                }
            }
        }
    }
}*/

template<typename F, typename T>
__global__ void coarse_col_rotate(F fn, int d3, int d2, int d1, int master, T* d, int num_cycle) {
    __shared__ T smem[32 * 2];
    int warp_id = threadIdx.x & 0x1f;
    
    //size_t l = chunk_left(blockIdx.x, gridDim.x, d3);
    //size_t r = chunk_right(blockIdx.x, gridDim.x, d3);
    size_t d1d2 = (size_t)d1 * (size_t)d2;
	size_t cycled3 = (size_t)num_cycle * (size_t)d3;
    //for (int k = l; k < r; k++) {
		int col = threadIdx.x + master;
        if (col < d1) {
            int rotation_amount = fn(master);
			row_major_index rm(d2, d1);
			int l = d2 / num_cycle;
			size_t inc = d2 - rotation_amount;
			int smem_write_idx = threadIdx.y * 32 + threadIdx.x;
			int max_col = (l > 2) ? 1 : l - 1;
			int smem_read_col = (threadIdx.y == 0) ? max_col : (threadIdx.y - 1);
			int smem_read_idx = smem_read_col * 32 + threadIdx.x;
			
		//for (size_t srck = blockIdx.x; srck < cycled3; srck += gridDim.x) {
			size_t k = blockIdx.x / num_cycle;
			size_t offset = k * d1d2;
			int b = blockIdx.x % num_cycle;
			//for(int b = 0; b < c; b++) {
				size_t x = threadIdx.y;
				size_t pos = ((size_t)b + x * inc) % (size_t)d2;   // (b + x * inc) % d2
				//int pos = d2.mod(b + x * inc);   // (b + x * inc) % d2
				smem[smem_write_idx] = d[offset + rm(pos, col)];
				__syncthreads();
				T prior = smem[smem_read_idx];
				if (x < l) d[offset + rm(pos, col)] = prior;
				int n_rounds = l / 2;
				for(int i = 1; i < n_rounds; i++) {
					x += blockDim.y;
					pos = ((size_t)b + x * inc) % (size_t)d2;   // (b + x * inc) % d2
					//int pos = d2.mod(b + x * inc);            
					if (x < l) smem[smem_write_idx] = d[offset + rm(pos, col)];
					__syncthreads();
					T incoming = smem[smem_read_idx];
					T outgoing = (threadIdx.y == 0) ? prior : incoming;
					if (x < l) d[offset + rm(pos, col)] = outgoing;
					prior = incoming;
				}
				//Last round/cleanup
				x += blockDim.y;
				pos = ((size_t)b + x * inc) % (size_t)d2;
				//pos = d2.mod(b + x * inc);
				if (x <= l) smem[smem_write_idx] = d[offset + rm(pos, col)];
				int remainder_length = (l % 2);
				int fin_smem_read_col = (threadIdx.y == 0) ? remainder_length : threadIdx.y - 1;
				int fin_smem_read_idx = fin_smem_read_col * 32 + threadIdx.x;
				__syncthreads();
				T incoming = smem[fin_smem_read_idx];
				T outgoing = (threadIdx.y == 0) ? prior : incoming;
				if (x <= l) d[offset + rm(pos, col)] = outgoing;
				
			//}
        //}
    }
}

template<typename F, typename T>
__global__ void fine_col_rotate(F fn, int d3, int d2, int d1, T* d) {
    __shared__ T smem[32 * 32]; 

    //If the whole warp is rotating by 0, early exit
    
    //size_t l = chunk_left(blockIdx.x, gridDim.x, d3);
    //size_t r = chunk_right(blockIdx.x, gridDim.x, d3);
    size_t d1d2 = (size_t)d1 * (size_t)d2;
    int warp_id = threadIdx.x & 0x1f;
    for (int k = blockIdx.x; k < d3; k += gridDim.x) {
    //for (int k = l; k < r; k++) {
        size_t offset = k * d1d2;
        for (int col = threadIdx.x + blockIdx.y * blockDim.x; col < d1; col += gridDim.y * blockDim.x) {
            //int col = threadIdx.x + blockIdx.x * blockDim.x;
            int coarse_rotation_amount = fn(fn.master(col, warp_id, 32));
            int overall_rotation_amount = fn(col);
            int fine_rotation_amount = overall_rotation_amount - coarse_rotation_amount;
            if (fine_rotation_amount < 0) fine_rotation_amount += d2;
            unsigned warp_vote = __ballot_sync(0xffffffff, fine_rotation_amount > 0);
            if (warp_vote > 0) {
                int row = threadIdx.y;
                int idx = row * d1 + col;
                T* read_ptr = d + offset + idx;
            
                int smem_idx = threadIdx.y * 32 + threadIdx.x;

                T first = -2;
                if (row < d2) first = *read_ptr;

                bool first_phase = (threadIdx.y >= fine_rotation_amount);
                int smem_row = threadIdx.y - fine_rotation_amount;
                if (!first_phase) smem_row += 32;

                int smem_write_idx = smem_row * 32 + threadIdx.x;

                if (first_phase) smem[smem_write_idx] = first;

                T* write_ptr = read_ptr;
                int ptr_inc = 32 * d1;
                read_ptr += ptr_inc;
                //Loop over blocks that are guaranteed not to fall off the edge
                for(int i = 0; i < (d2 / 32) - 1; i++) {
                    T tmp = *read_ptr;
                    if (!first_phase) smem[smem_write_idx] = tmp;
                    __syncthreads();
                    *write_ptr = smem[smem_idx];
                    __syncthreads();
                    if (first_phase) smem[smem_write_idx] = tmp;
                    write_ptr = read_ptr;
                    read_ptr += ptr_inc;
                }

                //Final block (read_ptr may have fallen off the edge)
                int remainder = d2 % 32;
                T tmp = -3;
                if (threadIdx.y < remainder) tmp = *read_ptr;
                int tmp_dest_row = 32 - fine_rotation_amount + threadIdx.y;
                if ((tmp_dest_row >= 0) && (tmp_dest_row < 32))
                    smem[tmp_dest_row * 32 + threadIdx.x] = tmp;
                __syncthreads();
                int first_dest_row = 32 + remainder - fine_rotation_amount + threadIdx.y;
                if ((first_dest_row >= 0) && (first_dest_row < 32))
                    smem[first_dest_row * 32 + threadIdx.x] = first;
            
                __syncthreads();
                *write_ptr = smem[smem_idx];
                write_ptr = read_ptr;
                __syncthreads();
                //Final incomplete block
                tmp_dest_row -= 32; first_dest_row -= 32;
                if ((tmp_dest_row >= 0) && (tmp_dest_row < 32))
                    smem[tmp_dest_row * 32 + threadIdx.x] = tmp;
                __syncthreads();
                if ((first_dest_row >= 0) && (first_dest_row < 32))
                    smem[first_dest_row * 32 + threadIdx.x] = first;
                __syncthreads();
                if (threadIdx.y < remainder) *write_ptr = smem[smem_idx];
            }
        }
    }
}

template<typename F, typename T>
__global__ void small_d1d2_rotate(F fn, int d3, int d2, int d1, T* d) {
	T* smem = shared_memory<T>();
	row_major_index rm(d2, d1);
	size_t d1d2 = (size_t)d1 * (size_t)d2;
	for (size_t k = blockIdx.x; k < d3; k += gridDim.x) {
		size_t offset = k * d1d2;
		__syncthreads();
		for (size_t idx = threadIdx.x; idx < d1d2; idx += blockDim.x) {
			size_t j = idx % d1;
			size_t i = ((idx / d1) - fn(j) + d2) % d2;
			smem[rm(i, j)] = d[offset + idx];
		}
		__syncthreads();
		for (size_t idx = threadIdx.x; idx < d1d2; idx += blockDim.x) {
			d[offset + idx] = smem[idx];
		}
	}
}

template<typename F, typename T>
void cycle_coarse_enact(F fn, int d3, int d2, int d1, T* data) {
	int num_block_d1 = div_up(d1, 32);
	for (int i = 0; i < num_block_d1; i++) {
		int master = i * 32;
		int rotation_amount = d2 - fn(master);
		int n_cycle = (rotation_amount == d2)? 0 : std::__gcd(rotation_amount, d2);
		if (n_cycle <= 0) continue;
		printf("n_cycle = %d, len = %d\n", n_cycle, d2 / n_cycle);
		dim3 block_dim(32, 2);
		int n_threads = block_dim.x * block_dim.y;
		//int n_blocks = min(d3, get_num_block(coarse_col_rotate<F, T>, n_threads, sizeof(T) * n_threads));
		int n_blocks = d3*n_cycle;//get_num_block(coarse_col_rotate<F, T>, n_threads, sizeof(T) * n_threads);
		printf("n_blocks = %d\n", n_blocks);
		coarse_col_rotate<<<n_blocks, block_dim>>>(fn, d3, d2, d1, master, data, n_cycle);
	}
}

template<typename F, typename T>
void rotate(F fn, int d3, int d2, int d1, T* data) {
	size_t smem_size = d1 * d2 * sizeof(T);
	if (smem_size <= shared_mem_per_block()) {
		//printf("small_d1d2_rotate\n");
		int n_threads = 1024;
		int n_blocks = min(d3, get_num_block(small_d1d2_rotate<F, T>, n_threads, smem_size));
		small_d1d2_rotate<<<n_blocks, n_threads, smem_size>>>(fn, d3, d2, d1, data);
	}
	else {
		if (fn.fine()) {
			dim3 block_dim(32, 32);
			int n_threads = block_dim.x * block_dim.y;
			int n_blocks_x = min(d3, get_num_block(fine_col_rotate<F, T>, n_threads, sizeof(T) * n_threads));
			int n_blocks_y = (n_blocks_x + d3 - 1) / d3;
			dim3 grid_dim(n_blocks_x, n_blocks_y);
			//printf("n_blocks = %d\n", get_num_block(fine_col_rotate<F, T>, n_threads, sizeof(T) * n_threads));
			fine_col_rotate<<<grid_dim, block_dim>>>(fn, d3, d2, d1, data);
		}
		//dim3 block_dim(32, 2);
		//int n_threads = block_dim.x * block_dim.y;
		//int n_blocks_x = min(d3, get_num_block(coarse_col_rotate<F, T>, n_threads, sizeof(T) * n_threads));
		//int n_blocks_y = (n_blocks_x + d3 - 1) / d3;
		//dim3 grid_dim(n_blocks_x, n_blocks_y);
		
		cycle_coarse_enact(fn, d3, d2, d1, data);
		//coarse_col_rotate<<<grid_dim, block_dim>>>(
		//	fn, d3, d2, d1, data);
		
		//coarse_launch(fn, d3, d2, d1, data);
	}
}

template void rotate(c2r::prerotator, int, int, int, float*);
template void rotate(c2r::prerotator, int, int, int, double*);
template void rotate(c2r::prerotator, int, int, int, int*);
template void rotate(c2r::prerotator, int, int, int, long long*);

template void rotate(c2r::postrotator, int, int, int, float*);
template void rotate(c2r::postrotator, int, int, int, double*);
template void rotate(c2r::postrotator, int, int, int, int*);
template void rotate(c2r::postrotator, int, int, int, long long*);

template void rotate(r2c::prerotator, int, int, int, float*);
template void rotate(r2c::prerotator, int, int, int, double*);
template void rotate(r2c::prerotator, int, int, int, int*);
template void rotate(r2c::prerotator, int, int, int, long long*);

template void rotate(r2c::postrotator, int, int, int, float*);
template void rotate(r2c::postrotator, int, int, int, double*);
template void rotate(r2c::postrotator, int, int, int, int*);
template void rotate(r2c::postrotator, int, int, int, long long*);


}
}
