/*
 * Common utilities
 *
 * Copyright 2010 Rasmus Andersson <http://hunch.se/>
 * Licensed under the MIT license.
 */
#ifndef H_COMMON_H_
#define H_COMMON_H_

#import <libkern/OSAtomic.h>

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
 *    BOOL h_casptr(void *oldval, void *newval, void *volatile *target)
 */
#define h_casptr(oldval, newval, target) OSAtomicCompareAndSwapPtrBarrier( \
    (void*)oldval, (void*)(newval), (void*volatile*)(target) )


#ifdef __OBJC__
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
 *      h_casid(&foo_, foo);
 *    }
 */
static inline BOOL h_casid(id volatile *target, id newval) {
  id oldval = *target;
  if (h_casptr(oldval, newval, target)) {
    [newval retain];
    [oldval release];
    return YES;
  }
  return NO;
}

#endif // __OBJC__


#endif // H_COMMON_H_
