import os
from glob import glob
from time import time
import numpy as np
import scipy.sparse as sp
import truthy_measure.closure as clo
from nose.tools import raises, nottest
from functools import partial

from truthy_measure.utils import DirTree, coo_dtype, fromdirtree

def test_closure_big():
    '''
    Speed test Python/Cython on large matrix
    '''
    np.random.seed(100)
    N = 500
    thresh = 0.1
    A = sp.rand(N, N, thresh, 'csr') 
    nnz = A.getnnz()
    sparsity = float(nnz) / N ** 2
    A = np.asarray(A.todense())
    source = 0
    tic = time()
    dists, paths = clo.closuress(A, source)
    toc = time()
    py_time = toc - tic
    tic = time()
    dists2, paths2 = clo.cclosuress(A, source)
    toc = time()
    cy_time = toc - tic
    assert np.allclose(dists, dists2)
    assert py_time > cy_time, \
            'python: {:.2g} s, cython: {:.2g} s.'.format(py_time, cy_time)

def test_closure_small():
    A = np.asarray([
        [0.0, 0.1, 0.0, 0.2],
        [0.0, 0.0, 0.3, 0.0],
        [0.0, 0.0, 0.0, 0.0],
        [0.0, 0.3, 0.0, 0.0]
        ])
    source = 0
    dists, paths = clo.closuress(A, source)
    dists2, paths2 = clo.cclosuress(A, source, retpaths=1)
    assert np.allclose(dists, dists2)
    for p1, p2 in zip(paths, paths2):
        assert np.all(p1 == p2)

def test_closure_rand():
    np.random.seed(21)
    N = 10
    sparsity = 0.3
    A = sp.rand(N, N, sparsity, 'csr')
    pyss = partial(clo.closuress, A)
    cyss = partial(clo.cclosuress, A, retpaths = 1)
    dists1, paths1 = zip(*map(pyss, xrange(N)))
    dists1 = np.asarray(dists1)
    paths1 = reduce(list.__add__, paths1)
    dists2, paths2 = zip(*map(cyss, xrange(N)))
    dists2 = np.asarray(dists2)
    paths2 = reduce(list.__add__, paths2)
    assert np.allclose(dists1, dists2)
    for p1, p2 in zip(paths1, paths2):
        assert np.all(p1 == p2)

def test_closureap():
    '''
    Correctedness of all-pairs parallel closure
    '''
    np.random.seed(100)
    dt = DirTree('test', (2, 5, 10), root='test_parallel')
    N = 100
    thresh = 0.1
    A = sp.rand(N, N, thresh, 'csr') 
    nnz = A.getnnz()
    sparsity = float(nnz) / N ** 2
    print 'Number of nnz = {}, sparsity = {:g}'.format(nnz, sparsity)
    A = np.asarray(A.todense())
    clo.closureap(A, dt)
    coords = np.asarray(fromdirtree(dt, N), dtype=coo_dtype)
    B = np.asarray(sp.coo_matrix((coords['weight'], (coords['row'], coords['col'])),
        shape=(N,N)).todense())
    rows = []
    for row in xrange(N):
        r, _ = clo.cclosuress(A, row)
        rows.append(r)
    C = np.asarray(rows)
    assert np.allclose(B, C)
    # cleanup
    for logpath in glob('closure-*.log'):
        os.remove(logpath)

def test_closure():
    np.random.seed(20)
    N = 10
    A = sp.rand(N, N, 1e-2, 'csr')
    source, target = np.random.randint(0, N, 2)
    cap1, path1 = clo.closure(A, source, target)
    cap2, path2 = clo.cclosure(A, source, target, retpath = 1)
    assert cap1 == cap2
    assert np.all(path1 == path2)

