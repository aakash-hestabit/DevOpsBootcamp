'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { api, type Product } from '@/lib/api';
import ProductForm from '@/components/ProductForm';

export default function ProductsPage() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);

  const fetchProducts = async () => {
    setLoading(true);
    setError('');
    try {
      const response = await api.listProducts();
      setProducts(response.data);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchProducts();
  }, []);

  const handleCreate = async (data: { name: string; description?: string; price: number; stock_quantity: number }) => {
    await api.createProduct(data);
    setShowCreateForm(false);
    await fetchProducts();
  };

  const handleUpdate = async (data: { name: string; description?: string; price: number; stock_quantity: number }) => {
    if (editingProduct) {
      await api.updateProduct(editingProduct.id, data);
      setEditingProduct(null);
      await fetchProducts();
    }
  };

  const handleDelete = async (id: number) => {
    if (!confirm('Are you sure you want to delete this product?')) return;
    try {
      await api.deleteProduct(id);
      await fetchProducts();
    } catch (err) {
      alert((err as Error).message);
    }
  };

  return (
    <div className="space-y-8 animate-fade-in">
      {/* Header */}
      <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
        <div>
          <h1 className="text-4xl font-bold bg-gradient-to-r from-indigo-600 to-purple-600 bg-clip-text text-transparent mb-2">Products</h1>
          <p className="text-gray-600 text-lg">Manage your inventory with ease</p>
        </div>
        <Link
          href="/"
          className="flex items-center gap-2 px-6 py-3 rounded-xl text-indigo-600 hover:bg-indigo-50 border border-indigo-200 font-semibold transition-all duration-200 hover:scale-105"
        >
          <span>←</span> Dashboard
        </Link>
      </div>

      {/* Error Display */}
      {error && (
        <div className="bg-red-50/80 backdrop-blur-sm border-l-4 border-red-500 rounded-xl p-6 shadow-md animate-slide-in">
          <div className="flex items-center gap-4">
            <span className="text-3xl">⚠️</span>
            <div>
              <h3 className="font-bold text-red-900 mb-1">Error Loading Products</h3>
              <p className="text-red-700 text-sm">{error}</p>
            </div>
          </div>
        </div>
      )}

      {/* Create Form - Collapsible Section */}
      {showCreateForm && (
        <div className="bg-gradient-to-br from-indigo-50 to-purple-50 rounded-2xl border-2 border-indigo-200 p-8 shadow-lg animate-fade-in">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-2xl font-bold text-indigo-900">✨ Create New Product</h2>
            <button
              onClick={() => setShowCreateForm(false)}
              className="text-indigo-400 hover:text-indigo-600 text-2xl font-bold transition-colors"
            >
              ×
            </button>
          </div>
          <ProductForm
            onSubmit={handleCreate}
            onCancel={() => setShowCreateForm(false)}
            submitLabel="Create Product"
          />
        </div>
      )}

      {/* Add Product Button */}
      {!showCreateForm && !editingProduct && (
        <button
          onClick={() => setShowCreateForm(true)}
          className="w-full md:w-auto px-8 py-4 rounded-xl bg-gradient-to-r from-indigo-600 to-purple-600 text-white font-bold text-lg hover:shadow-lg hover:shadow-indigo-500/30 transition-all duration-200 transform hover:scale-105 flex items-center justify-center gap-2 group"
        >
          <span className="group-hover:rotate-90 transition-transform duration-300">➕</span> Add New Product
        </button>
      )}

      {/* Loading State */}
      {loading && (
        <div className="flex flex-col items-center justify-center py-24">
          <div className="w-16 h-16 rounded-full border-4 border-gray-200 border-t-indigo-600 animate-spin mb-4"></div>
          <p className="text-gray-600 font-semibold">Loading products...</p>
        </div>
      )}

      {/* Empty State */}
      {!loading && products.length === 0 && (
        <div className="bg-white/80 backdrop-blur-sm rounded-2xl border-2 border-dashed border-gray-300 p-16 text-center shadow-sm hover:shadow-lg transition-all duration-300">
          <div className="text-6xl mb-4">📦</div>
          <h3 className="text-2xl font-bold text-gray-900 mb-2">No Products Yet</h3>
          <p className="text-gray-600 mb-6">Create your first product to get started</p>
          <button
            onClick={() => setShowCreateForm(true)}
            className="px-8 py-3 rounded-xl bg-gradient-to-r from-indigo-600 to-purple-600 text-white font-semibold hover:shadow-lg hover:shadow-indigo-500/30 transition-all duration-200 inline-flex items-center gap-2"
          >
            <span>➕</span> Create First Product
          </button>
        </div>
      )}

      {/* Products Grid */}
      {!loading && products.length > 0 && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {products.map((product, index) => (
            <div 
              key={product.id} 
              className="bg-white/80 backdrop-blur-sm rounded-2xl border border-gray-200/50 p-8 shadow-sm hover:shadow-xl transition-all duration-300 transform hover:-translate-y-1 group animate-fade-in"
              style={{ animationDelay: `${index * 50}ms` }}
            >
              {editingProduct?.id === product.id ? (
                <div>
                  <h2 className="text-2xl font-bold text-indigo-900 mb-6">Edit Product</h2>
                  <ProductForm
                    product={editingProduct}
                    onSubmit={handleUpdate}
                    onCancel={() => setEditingProduct(null)}
                    submitLabel="Update Product"
                  />
                </div>
              ) : (
                <>
                  <div className="mb-6">
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex-1">
                        <h3 className="text-2xl font-bold text-gray-900 mb-2 group-hover:text-indigo-600 transition-colors">{product.name}</h3>
                        <span className="inline-block px-3 py-1 rounded-full bg-indigo-100 text-indigo-700 text-xs font-semibold">ID: {product.id}</span>
                      </div>
                    </div>
                    
                    {product.description && (
                      <p className="text-gray-600 text-sm leading-relaxed mt-3 p-3 bg-gray-50 rounded-lg">{product.description}</p>
                    )}
                  </div>

                  {/* Metrics */}
                  <div className="grid grid-cols-2 gap-4 mb-6 py-6 border-y border-gray-200">
                    <div className="bg-gradient-to-br from-green-50 to-emerald-50 rounded-lg p-4">
                      <p className="text-gray-600 text-xs font-semibold uppercase tracking-wide mb-1">Price</p>
                      <p className="text-3xl font-bold text-green-700">${product.price}</p>
                    </div>
                    <div className="bg-gradient-to-br from-blue-50 to-cyan-50 rounded-lg p-4">
                      <p className="text-gray-600 text-xs font-semibold uppercase tracking-wide mb-1">Stock</p>
                      <p className="text-3xl font-bold text-blue-700">{product.stock_quantity}</p>
                      <p className="text-xs text-gray-600 mt-1">{product.stock_quantity > 0 ? '✓ In Stock' : '⚠️ Out'}</p>
                    </div>
                  </div>

                  {/* Timestamps */}
                  <div className="text-xs text-gray-500 space-y-1 mb-6">
                    <div className="flex justify-between">
                      <span>Created:</span>
                      <span className="font-mono">{new Date(product.created_at).toLocaleDateString()} {new Date(product.created_at).toLocaleTimeString()}</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Updated:</span>
                      <span className="font-mono">{new Date(product.updated_at).toLocaleDateString()} {new Date(product.updated_at).toLocaleTimeString()}</span>
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="flex gap-3">
                    <button
                      onClick={() => setEditingProduct(product)}
                      className="flex-1 px-4 py-3 rounded-lg font-semibold text-indigo-700 bg-indigo-50 hover:bg-indigo-100 border border-indigo-200 transition-all duration-200 flex items-center justify-center gap-2 transform hover:scale-105"
                    >
                      <span>✏️</span> Edit
                    </button>
                    <button
                      onClick={() => handleDelete(product.id)}
                      className="flex-1 px-4 py-3 rounded-lg font-semibold text-red-700 bg-red-50 hover:bg-red-100 border border-red-200 transition-all duration-200 flex items-center justify-center gap-2 transform hover:scale-105"
                    >
                      <span>🗑️</span> Delete
                    </button>
                  </div>
                </>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
