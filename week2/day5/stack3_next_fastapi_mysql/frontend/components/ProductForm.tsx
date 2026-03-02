'use client';

import { useState } from 'react';
import type { Product } from '@/lib/api';

interface FormData {
  name: string;
  description: string;
  price: string;
  stock_quantity: string;
}

interface Props {
  product?: Product;
  onSubmit: (data: {
    name: string;
    description?: string;
    price: number;
    stock_quantity: number;
  }) => Promise<void>;
  onCancel?: () => void;
  submitLabel?: string;
}

export default function ProductForm({
  product,
  onSubmit,
  onCancel,
  submitLabel = 'Save',
}: Props) {
  const [form, setForm] = useState<FormData>({
    name: product?.name || '',
    description: product?.description || '',
    price: product?.price ? String(product.price) : '',
    stock_quantity: product ? String(product.stock_quantity) : '0',
  });

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>
  ) => {
    setForm((f) => ({ ...f, [e.target.name]: e.target.value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      await onSubmit({
        name: form.name,
        description: form.description || undefined,
        price: parseFloat(form.price),
        stock_quantity: parseInt(form.stock_quantity, 10),
      });
    } catch (err) {
      setError((err as Error).message || 'Something went wrong');
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Error */}
      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          <strong className="block font-semibold">Validation error</strong>
          {error}
        </div>
      )}

      {/* Product Name */}
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-800">
          Product Name <span className="text-red-500">*</span>
        </label>
        <input
          name="name"
          value={form.name}
          onChange={handleChange}
          required
          maxLength={100}
          placeholder="Premium Widget Pro"
          className="w-full rounded-lg border border-gray-300 bg-white px-4 py-2.5 text-sm text-gray-900
                     placeholder-gray-400 shadow-sm
                     focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        />
        <p className="mt-1 text-xs text-gray-500">
          {form.name.length}/100 characters
        </p>
      </div>

      {/* Description */}
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-800">
          Description
        </label>
        <textarea
          name="description"
          value={form.description}
          onChange={handleChange}
          rows={3}
          maxLength={1000}
          placeholder="Describe your product..."
          className="w-full resize-none rounded-lg border border-gray-300 bg-white px-4 py-2.5 text-sm text-gray-900
                     placeholder-gray-400 shadow-sm
                     focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        />
        <p className="mt-1 text-xs text-gray-500">
          {form.description.length}/1000 characters
        </p>
      </div>

      {/* Price + Stock */}
      <div className="grid grid-cols-1 gap-5 md:grid-cols-2">
        {/* Price */}
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-800">
            Price (USD) <span className="text-red-500">*</span>
          </label>
          <div className="relative">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500">
              $
            </span>
            <input
              name="price"
              type="number"
              step="0.01"
              min="0.01"
              value={form.price}
              onChange={handleChange}
              required
              placeholder="0.00"
              className="w-full rounded-lg border border-gray-300 bg-white py-2.5 pl-8 pr-4 text-sm text-gray-900
                         placeholder-gray-400 shadow-sm
                         focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            />
          </div>
        </div>

        {/* Stock */}
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-800">
            Stock Quantity
          </label>
          <div className="relative">
            <input
              name="stock_quantity"
              type="number"
              min="0"
              value={form.stock_quantity}
              onChange={handleChange}
              placeholder="0"
              className="w-full rounded-lg border border-gray-300 bg-white px-4 py-2.5 text-sm text-gray-900
                         placeholder-gray-400 shadow-sm
                         focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-gray-500">
              units
            </span>
          </div>
        </div>
      </div>

      {/* Preview */}
      {(form.name || form.price) && (
        <div className="rounded-lg border border-indigo-100 bg-indigo-50 p-4 text-sm">
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-indigo-700">
            Preview
          </p>
          <div className="space-y-1">
            <div className="flex justify-between">
              <span className="text-gray-600">Product</span>
              <span className="font-semibold text-gray-900">
                {form.name || '—'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-600">Price</span>
              <span className="font-semibold text-green-700">
                ${form.price || '0.00'}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-600">Stock</span>
              <span className="font-semibold text-blue-700">
                {form.stock_quantity || '0'} units
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Actions */}
      <div className="flex flex-col-reverse gap-3 pt-4 sm:flex-row">
        {onCancel && (
          <button
            type="button"
            onClick={onCancel}
            className="flex-1 rounded-lg border border-gray-300 px-5 py-2.5 text-sm font-semibold text-gray-700
                       hover:bg-gray-50"
          >
            Cancel
          </button>
        )}

        <button
          type="submit"
          disabled={loading}
          className="flex flex-1 items-center justify-center gap-2 rounded-lg
                     bg-gradient-to-r from-indigo-600 to-purple-600
                     px-5 py-2.5 text-sm font-semibold text-white
                     hover:shadow-lg hover:shadow-indigo-500/30
                     disabled:cursor-not-allowed disabled:opacity-60"
        >
          {loading ? (
            <>
              <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
              Processing…
            </>
          ) : (
            <>
              <span>💾</span>
              {submitLabel}
            </>
          )}
        </button>
      </div>
    </form>
  );
}