# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'vmpooler/api/request_logger'

describe Vmpooler::API::RequestLogger do
  let(:logger) { double('logger', log: nil) }
  let(:app) { ->(_env) { [201, { 'Content-Type' => 'application/json' }, ['{"ok":true}']] } }
  let(:middleware) { described_class.new(app, logger: logger) }
  let(:client) { Rack::MockRequest.new(middleware) }

  it 'keeps the app it wraps' do
    expect(middleware.app).to be(app)
  end

  it 'passes the response through unchanged' do
    response = client.post('/api/v3/vm/debian-7-x86_64')

    expect(response.status).to eq(201)
    expect(response.headers['Content-Type']).to eq('application/json')
    expect(response.body).to eq('{"ok":true}')
  end

  it 'logs the method, status, path and body of each request' do
    client.post('/api/v3/vm/debian-7-x86_64')

    expect(logger).to have_received(:log).with('s', %r{\[ \] API: Method: POST, Status: 201, Path: /api/v3/vm/debian-7-x86_64, Body: })
  end

  it 'logs every request' do
    client.get('/api/v3/status')
    client.delete('/api/v3/vm/host1')

    expect(logger).to have_received(:log).twice
  end
end
