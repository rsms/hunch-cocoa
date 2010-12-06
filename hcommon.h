/*
 * Common utilities
 *
 * Copyright 2010 Rasmus Andersson <http://hunch.se/>
 * Licensed under the MIT license.
 */
#ifndef H_COMMON_H_
#define H_COMMON_H_

/*
 * -- BEGIN LIBDISPATCH DERIVATIVES --
 *
 * Copyright (c) 2008-2009 Apple Inc. All rights reserved.
 *
 * @APPLE_APACHE_LICENSE_HEADER_START@
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * 
 * @APPLE_APACHE_LICENSE_HEADER_END@
 */
#if __GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 2)
  // GCC generates suboptimal register pressure
  // LLVM does better, but doesn't support tail calls
  // 6248590 __sync_*() intrinsics force a gratuitous "lea" instruction, with
  //         resulting register pressure
  // p = pointer to target, o = old value, n = new value
  #if 0 && defined(__i386__) || defined(__x86_64__)
    #define h_atomic_xchg(p, n)	({ typeof(*(p)) _r; asm("xchg %0, %1" : "=r" (_r) : "m" (*(p)), "0" (n)); _r; })
  #else
    #define h_atomic_xchg(p, n)	((typeof(*(p)))__sync_lock_test_and_set((p), (n)))
  #endif
  #define h_atomic_cas(p, o, n)	__sync_bool_compare_and_swap((p), (o), (n))
  #define h_atomic_inc(p)	__sync_add_and_fetch((p), 1)
  #define h_atomic_dec(p)	__sync_sub_and_fetch((p), 1)
  #define h_atomic_add(p, v)	__sync_add_and_fetch((p), (v))
  #define h_atomic_sub(p, v)	__sync_sub_and_fetch((p), (v))
  #define h_atomic_or(p, v)	__sync_fetch_and_or((p), (v))
  #define h_atomic_and(p, v)	__sync_fetch_and_and((p), (v))
  #if defined(__i386__) || defined(__x86_64__)
    // GCC emits nothing for __sync_synchronize() on i386/x86_64
    #define h_atomic_barrier()	__asm__ __volatile__("mfence")
  #else
    #define h_atomic_barrier()	__sync_synchronize()
  #endif
#else
  #error "Please upgrade to GCC 4.2 or newer"
#endif
// -- END LIBDISPATCH DERIVATIVES --


/*!
 * Atomically swap value of |target| with |newval| if the value of |target| is
 * |oldval| at the time of swapping. Returns YES if the swap was successful, or
 * NO if value of |target| changed before the compare-and-swap executed.
 *
 * Example:
 *    dispatch_source_t writeSource = foo->writeSource_;
 *    if (h_casptr(writeSource, nil, &(foo->writeSource_)))
 *      dispatch_release(writeSource);
 *
 * Prototype:
 *    BOOL h_casptr(void *volatile *target, void *oldval, void *newval)
 */
#define h_casptr(target, oldval, newval) h_atomic_cas( \
    (void*volatile*)(target), (void*)(oldval), (void*)(newval))


#ifdef __OBJC__

/*!
 * Atomically replace an Objective-C variable.
 *
 * After a successful swap, |newval| is send a "retain" message, the previous
 * value of |target| is sent a "release" message and YES is returned. If someone
 * else changed the value of |target| (before we executed our compare-and-swap),
 * NO is returned.
 *
 * If you need the previous value, consider using h_casptr instead.
 *
 * Example:
 *    - (void)setFoo:(id)foo {
 *      h_atomic_casid(&foo_, foo);
 *    }
 */
static inline BOOL h_casid(id volatile *target, id newval) {
  id oldval = *target;
  if (h_casptr(target, oldval, newval)) {
    [newval retain];
    [oldval release];
    return YES;
  }
  return NO;
}

/*!
 * Swap value of |target| with |newvval|, retaining |target| and releasing the
 * previous value of |target|. Returns the previous value of |target|.
 * Note: this is NOT an atomic operation. If you need atomicity, use h_casid.
 */
static inline id h_swapid(id *target, id newval) {
  id oldval = *target;
  *target = [newval retain];
  [oldval release];
  return oldval;
}

#endif // __OBJC__

#endif // H_COMMON_H_
