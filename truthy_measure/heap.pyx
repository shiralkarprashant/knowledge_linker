"""Cython implementation of a binary min heap.

Original author: Almar Klein
Modified by: Zachary Pincus

License: BSD

Copyright 2009 Almar Klein

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"""

from __future__ import division

# cython specific imports
import cython 
from libc.stdlib cimport malloc, free

cdef extern from "pyport.h":
  double Py_HUGE_VAL

cdef VALUE_T inf = Py_HUGE_VAL

# this is handy
cdef inline int int_max(int a, int b): return a if a >= b else b
cdef inline int int_min(int a, int b): return a if a <= b else b


cdef class BinaryHeap:
    """ The binary heap class
    
    BinaryHeap(initial_capacity=128)
    
    A binary heap is an object to store values in, optimized in such a way 
    that the minimum (or maximum, but a minimum in this implementation) 
    value can be found in O(log2(N)) time. In this implementation, a reference
    value (a single integer) can also be stored with each value.
    
    Use the methods push() and pop() to put in or extract values.
    In C, use the corresponding push_fast() and pop_fast().
    
    An initial capacity can be provided if an estimate of the size of the heap
    is known in advance, but in any case the heap will dynamically resize.
    
    ----- Documentation -----
    
    This implementation stores the binary heap in an array twice as long as
    the number of elements in the heap. The array is structured in levels,
    starting at level 0 with a single value, doubling the amount of values in
    each level. The final level contains the actual values, the level before
    it contains the pairwise minimum values. The level before that contains
    the pairwise minimum values of that level, etc. Take a look at this
    illustration:
    
    level: 0 11 2222 33333333 4444444444444444
    index: 0 12 3456 78901234 5678901234567890
                        1          2         3
    
     The actual values are stored in level 4. The minimum value of position 15
    and 16 is stored in position 7. min(17,18)->8, min(7,8)->3, min(3,4)->1.
    When adding a value, only the path to the top has to be updated, which
    takesO(log2(N)) time.
    
     The advantage of this implementation relative to more common
    implementations that swap values when pushing to the array is that data
    only needs to be swapped once when an element is removed. This means that
    keeping an array of references along with the values is very inexpensive.
    Th disadvantage is that if you pop the minimum value, the tree has to be
    traced from top to bottom and back. So if you only want values and no
    references, this implementation will probably be slower. If you need
    references (and maybe cross references to be kept up to date) this
    implementation will be faster.
    
     - count is the number of values 
     - levels is the number of levels (levels is also the last level, such 
       that 2**levels is the number of value in it)
    """
    
    ## Basic methods
    # The following lines are always "inlined", but documented here for
    # clarity:
    #
    # To calculate the start index of a certain level:
    # 2**l-1 # LevelStart
    # Note that in inner loops, this may also be represented as (1<<l)-1, 
    # because code of the form x**y goes via the python pow operations and 
    # can thus be a bit slower.
    #
    # To calculate the corresponding ABSOLUTE index at the next level:
    # i*2+1 # CalcNextAbs
    #
    # To calculate the corresponding ABSOLUTE index at the previous level:
    # (i-1)/2 # CalcPrevAbs
    #
    # To calculate the capacity at a certain level:
    # 2**l
    
    
    def __init__(self, int initial_capcity=128):
        """__init__(initial_capacity=128)
        
        Constructor: takes an optional parameter 'initial_capacity' so that
        if the required heap capacity is known or can be estimated in advance,
        there will need to be fewer resize operations on the heap."""
        
        # calc levels from the default capacity
        cdef int levels = 0
        while 2**levels < initial_capcity:
            levels += 1        
        # set levels
        self.min_levels = self.levels = levels
        
        # we start with 0 values
        self.count = 0
        
        # allocate arrays
        cdef int number = 2**self.levels
        cdef VALUE_T *values
        values = self._values = <VALUE_T *>malloc( 2*number * sizeof(VALUE_T))
        self._references = <REFERENCE_T *>malloc(number * sizeof(REFERENCE_T))
        
        self.reset()

    def reset(self):
        """Reset the heap to default, empty state."""
        cdef int number = 2**self.levels
        cdef int i
        cdef VALUE_T *values = self._values
        for i in range(number*2):
            values[i] = inf
    
    
    def __dealloc__(self):
        if self._values is not NULL:
            free(self._values)
        if self._references is not NULL:
            free(self._references)
        
    
        
    def __str__(self):
        cdef int i0, i, n, level
        s = ''
        for level in range(1,self.levels+1):
            i0 = 2**level-1 # LevelStart
            s+= 'level %i: ' % level
            for i in range(i0,i0+2**level):
                s += '%g, ' % self._values[i]
            s = s[:-1] + '\n'
        return s
    
    
    ## C Maintanance methods
    
    cdef void _add_or_remove_level(self, int add_or_remove):
        # init indexing ints
        cdef int i, i1, i2, n
        
        # new amount of levels
        cdef int new_levels = self.levels + add_or_remove
        
        # allocate new arrays
        cdef int number = 2**new_levels
        cdef VALUE_T *values  
        cdef REFERENCE_T *references
        values = <VALUE_T *>malloc(number*2 * sizeof(VALUE_T))
        references = <REFERENCE_T *>malloc(number * sizeof(REFERENCE_T))
        
        # init arrays 
        for i in range(number*2):
            values[i] = inf
        for i in range(number):
            references[i] = -1
        
        # copy data
        cdef VALUE_T *old_values = self._values
        cdef REFERENCE_T *old_references = self._references
        if self.count:
            i1 = 2**new_levels-1 # LevelStart
            i2 = 2**self.levels-1 # LevelStart
            n = int_min(2**new_levels, 2**self.levels)
            for i in range(n):
                values[i1+i] = old_values[i2+i]
            for i in range(n):
                references[i] = old_references[i]
        
        # make current
        free(self._values)
        free(self._references)
        self._values = values
        self._references = references
        
        # we need a full update
        self.levels = new_levels
        self._update()
    
    
    cdef void _update(self):
        """Update the full tree from the bottom up. 
        This should be done after resizing. """
        
        # shorter name for values
        cdef VALUE_T *values = self._values
        
        # Note that i represents an absolute index here
        cdef int i0, i, ii, n, level
        
        # track tree
        for level in range(self.levels,1,-1):        
            i0 = (1 << level) - 1 #2**level-1 = LevelStart
            n = i0 + 1 #2**level
            for i in range(i0,i0+n,2):            
                ii = (i-1)//2 # CalcPrevAbs
                if values[i] < values[i+1]:
                    values[ii] = values[i]
                else:
                    values[ii] = values[i+1]
    
    
    cdef void _update_one(self, int i):
        """Update the tree for one value."""
        
        # shorter name for values
        cdef VALUE_T *values = self._values
        
        # make index uneven
        if i % 2==0:
            i = i-1
                
        # track tree        
        cdef int ii, level      
        for level in range(self.levels,1,-1):        
            ii = (i-1)//2 # CalcPrevAbs
            # test
            if values[i] < values[i+1]:
                values[ii] = values[i]
            else:
                values[ii] = values[i+1]
            # next
            if ii % 2:
                i = ii
            else:
                i = ii-1
    
    
    cdef void _remove(self, int i1):
        """Remove a value from the heap. By index."""
        
        cdef int levels = self.levels
        cdef int count = self.count
        # get indices
        cdef int i0 = (1 << levels) - 1  #2**self.levels - 1 # LevelStart
        cdef int i2 = i0 + count - 1        
        
        # get relative indices
        cdef int r1 = i1 - i0
        cdef int r2 = count - 1
        
        cdef VALUE_T *values = self._values
        cdef REFERENCE_T *references = self._references
        
        # swap with last        
        values[i1] = values[i2]
        references[r1] = references[r2]
        
        # make last Null
        values[i2] = inf
        
        # update
        self.count -= 1
        count -= 1
        if (levels>self.min_levels) & (count < (1 << (levels-2))):
            self._add_or_remove_level(-1)
        else:
            self._update_one(i1)
            self._update_one(i2)
    
    
    ## C Public methods
    
    cdef int push_fast(self, double value, int reference):
        """The c-method for fast pushing.
        
        Returns the index relative to the start of the last level in the heap."""
        # We need to resize if currently it just fits.
        cdef int levels = self.levels
        cdef int count = self.count
        if count >= (1 << levels):#2**self.levels:
            self._add_or_remove_level(+1)
            levels += 1
            
        # insert new value
        cdef int i = ((1 << levels) - 1) + count # LevelStart + n
        self._values[i] = value
        self._references[count] = reference
        
        # update        
        self.count += 1
        self._update_one(i)
        
        # return 
        return count
    
    
    cdef float pop_fast(self):
        """The c-method for fast popping.
        
        Returns the minimum value. The reference is put in self._popped_ref"""
        
        # shorter name for values
        cdef VALUE_T *values = self._values
        
        # init index. start at 1 because we start in level 1
        cdef int level
        cdef int i = 1
        cdef int levels = self.levels
        # search tree (using absolute indices)
        for level in range(1, levels):        
            if values[i] < values[i+1]:
                i = i*2+1 # CalcNextAbs
            else:
                i = (i+1)*2+1 # CalcNextAbs
        
        # select best one in last level
        if values[i] < values[i+1]:
            i = i
        else:
            i = i+1
        
        # get values
        cdef int ir = i - ((1 << levels) - 1) #(2**self.levels-1) # LevelStart
        cdef float value =  values[i]
        self._popped_ref = self._references[ir]
        
        # remove it
        if value != inf:
            self._remove(i)
        
        # return 
        return value
    
    
    ## Python Public methods (that do not need to be VERY fast)
    
    def push(self, double value, int reference=-1):
        """push(value, reference=-1)
        
        Append a value to the heap, with optional reference. """        
        self.push_fast(value, reference)
    
    
    def min_val(self):
        """Get the minimum value.
       
        Returns only the value, and does not remove it from the heap."""
        
        # shorter name for values
        cdef VALUE_T *values = self._values
        
        # select best one in last level
        if values[1] < values[2]:
            return values[1]
        else:
            return values[2]
    
    
    def values(self):
        """Get the values in the heap as a list."""
        out = []
        cdef int i, i0
        i0 = 2**self.levels-1  # LevelStart
        for i in range(self.count):
            out.append( self._values[i0+i] )
        return out
    
    
    def references(self):
        """Get the references in the heap as a list."""
        out = []
        cdef int i
        for i in range(self.count):
            out.append( self._references[i] )
        return out
    
    
    def pop(self):
        """Get the minimum value and remove it from the list. 
        
        Returns a tuple of (value, reference) 
        If the queue is empty, an IndexError is raised.
        """
        if self.count == 0:
          raise IndexError('pop from an empty heap')
        value = self.pop_fast()
        ref = self._popped_ref
        return value, ref
    


cdef class FastUpdateBinaryHeap(BinaryHeap):
    """FastUpdateBinaryHeap(initial_capacity=128, max_reference=None)
    
    A binary heap that keeps cross-references so that the value of a given
    reference can be quickly queried (O(1) time) or updated (O(log2(N)) time).
    This is ideal for pathfinding algorithms that implement some variant of
    Dijkstra's algorithm.
        
    At initialization, provide the largest reference value that might be
    pushed to the heap. (Pushing a larger value will result in an error.) If
    no value is provided, 1-initial_capacity will be used. For the cross-
    reference index to work, all references must be in the range 
    [0, max_reference]; references pushed outside of that range will not be
    added to the heap.
    
    The cross-references map data[reference]->internalindex, such that the
    value corresponding to a given reference can be found efficiently. This
    can be queried with the value_of() method. (value_of_fast() in C)
    
    Finally, note that a special method, push_if_lower() (push_if_lower_fast()
    in C) is provided that will update the heap if the given reference is not
    in the heap, or if it is and the provided value is lower than the current
    value in the heap. This is again useful for pathfinding algorithms.
    
    """    
    def __init__(self, int initial_capacity=128, max_reference=None):
        """__init__(initial_capacity=128, max_reference=None)
        
        Constructor: takes optional initial_capacity (but the heap size can 
        still grow dynamically) and max_reference (which is a max for the
        lifetime of the heap, and sets a de-facto cap on the maximum heap
        size.)"""
        if max_reference is None:
          max_reference = initial_capacity - 1
        self.max_reference = max_reference
        self._crossref = <REFERENCE_T *>malloc((max_reference+1) * sizeof(REFERENCE_T))
        # below will call self.reset
        BinaryHeap.__init__(self, initial_capacity)
        
    def __dealloc__(self):
        if self._crossref is not NULL:
            free(self._crossref)

    def reset(self):
        """Reset the heap to default, empty state."""
        BinaryHeap.reset(self)
        # set default values of crossrefs
        cdef int i
        for i in range(self.max_reference+1):
            self._crossref[i] = -1
    
    
    cdef void _remove(self, int i1):
        """ Remove a value from the heap. By index. """
        cdef int levels = self.levels
        cdef int count = self.count
        
        # get indices
        cdef int i0 = (1 << levels) - 1  #2**self.levels - 1 # LevelStart
        cdef int i2 = i0 + count - 1        
        
        # get relative indices
        cdef int r1 = i1 - i0
        cdef int r2 = count - 1
        
        cdef VALUE_T *values = self._values
        cdef REFERENCE_T *references = self._references
        cdef REFERENCE_T *crossref = self._crossref
        
        # update cross reference        
        crossref[references[r2]]=r1
        crossref[references[r1]]=-1  # disable removed item
        
        # swap with last        
        values[i1] = values[i2]
        references[r1] = references[r2]        
        
        # make last Null
        values[i2] = inf
        
        # update
        self.count -= 1
        count -= 1
        if (levels>self.min_levels) & (count < (1 << (levels-2))):
            self._add_or_remove_level(-1)
        else:
            self._update_one(i1)
            self._update_one(i2)
    
    
    cdef int push_fast(self, double value, int reference):
        """The c method for fast pushing.
        
        If the reference is already present, will update its value, otherwise
        will append it.
        
        If -1 is returned, the provided reference was out-of-bounds and no 
        value was pushed to the heap."""
        if not (0 <= reference <= self.max_reference):
          return -1
                  
        # init variable to store the index-in-the-heap
        cdef int i
        
        # Reference is the index in the array where MCP is applied to.
        # Find the index-in-the-heap using the crossref array.
        cdef int ir = self._crossref[reference]
        
        if ir != -1:
            # update
            i = (1 << self.levels) - 1 + ir
            self._values[i] = value
            self._update_one(i)
            return ir
        
        # if not updated: append normally and store reference
        ir = BinaryHeap.push_fast(self, value, reference)
        self._crossref[reference] = ir
        return ir

    cdef int push_if_lower_fast(self, double value, int reference):
        """If the reference is already present, will update its value ONLY if
        the new value is lower than the old one. If the reference is not
        present, this append it. If a value was appended, self._pushed is
        set to 1.
        
        If -1 is returned, the provided reference was out-of-bounds and no 
        value was pushed to the heap.
        """
        if not (0 <= reference <= self.max_reference):
            return -1
                  
        # init variable to store the index-in-the-heap
        cdef int i
        
        # Reference is the index in the array where MCP is applied to.
        # Find the index-in-the-heap using the crossref array.
        cdef int ir = self._crossref[reference]
        cdef VALUE_T *values = self._values
        self._pushed = 1
        if ir != -1:
            # update
            i = (1 << self.levels) - 1 + ir
            if values[i] > value:
                values[i] = value
                self._update_one(i)
            else:
                self._pushed = 0
            return ir
        
        # if not updated: append normally and store reference
        ir = BinaryHeap.push_fast(self, value, reference)        
        self._crossref[reference] = ir
        return ir

    
    cdef float value_of_fast(self, int reference):
        """Return the value corresponding to the given reference. If inf
        is returned, the reference may be invalid: check the _invaild_ref
        field in this case."""
        # init variable to store the index-in-the-heap
        cdef int i
    
        # Reference is the index in the array where MCP is applied to.
        # Find the index-in-the-heap using the crossref array.
        cdef int ir = self._crossref[reference]
        self._invalid_ref = 0
        if ir == -1:
            self._invalid_ref = 1
            return inf
        i = (1 << self.levels) - 1 + ir
        return self._values[i]
    
    
    def push(self, double value, int reference):        
        """push(value, reference)
        
        Append/update a value in the heap.
        If the reference is already present, will update its value, otherwise
        will append it.
        """
        if self.push_fast(value, reference) == -1:
          raise ValueError("reference outside of range [0, max_reference]")
    
    def push_if_lower(self, double value, int reference):        
        """push_if_lower(value, reference)
        
        Append/update a value in the heap. If the reference is already in the 
        heap, update only of the new value is lower than the current one.
        If the reference is not present, this will append it.
        Returns True if an append/update occured, False if otherwise.
        """
        if self.push_if_lower_fast(value, reference) == -1:
          raise ValueError("reference outside of range [0, max_reference]")
        return self._pushed == 1
    
    def value_of(self, int reference):
      """value_of(reference)
      
      Get the value corresponding to a given reference already pushed into 
      the heap.
      """
      value = self.value_of_fast(reference)
      if self._invalid_ref:
          raise ValueError('invalid reference')
      return value
    
    def cross_references(self):
        """Get the cross references in the heap as a list."""
        out = []
        cdef int i
        for i in range(self.max_reference+1):
            out.append( self._crossref[i] )
        return out
    

## TESTS

def test(int n, fast_update=False):
    """Test the binary heap."""
    import time
    import random
    # generate random numbers with duplicates
    random.seed(0)
    a = [random.uniform(1.0,100.0) for i in range(n//2)]
    a = a+a
    
    t0 = time.clock()
    
    # insert in heap with random removals
    if fast_update:
        h = FastUpdateBinaryHeap(128, n)
    else:
        h = BinaryHeap(128)
    for i in range(len(a)):
        h.push(a[i], i)
        if a[i] < 25:
          # double-push same ref sometimes to test fast update codepaths
          h.push(2*a[i], i)
        if 25 < a[i] < 50:
          # pop some to test random removal
          h.pop()
    
    # pop from heap
    b = []
    while True:
        try:
            b.append(h.pop()[0])
        except IndexError:
            break
    
    t1 = time.clock()
    
    # verify
    for i in range(1,len(b)):
        if b[i] < b[i-1]:
            print 'error in order!'
    
    print 'elapsed time:', t1-t0
    return b

