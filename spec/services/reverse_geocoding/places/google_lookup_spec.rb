# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReverseGeocoding::Places::GoogleLookup do
  let(:endpoint) { 'https://places.googleapis.com/v1/places:searchNearby' }
  let(:api_response) do
    {
      'places' => [
        {
          'id' => 'ChIJabc123',
          'displayName' => { 'text' => 'Blue Bottle Coffee', 'languageCode' => 'en' },
          'location' => { 'latitude' => 35.6812, 'longitude' => 139.7671 },
          'types' => %w[cafe food point_of_interest],
          'primaryType' => 'cafe',
          'addressComponents' => [
            { 'longText' => '1', 'shortText' => '1', 'types' => ['street_number'] },
            { 'longText' => 'Marunouchi', 'shortText' => 'Marunouchi', 'types' => ['route'] },
            { 'longText' => 'Chiyoda City', 'shortText' => 'Chiyoda', 'types' => ['locality'] },
            { 'longText' => 'Tokyo', 'shortText' => 'Tokyo', 'types' => ['administrative_area_level_1'] },
            { 'longText' => 'Japan', 'shortText' => 'JP', 'types' => ['country'] },
            { 'longText' => '100-0005', 'shortText' => '100-0005', 'types' => ['postal_code'] }
          ]
        }
      ]
    }
  end

  before do
    stub_const('GOOGLE_PLACES_API_KEY', 'test-key')
    stub_const('GOOGLE_PLACES_LANGUAGE', 'ja')

    stub_request(:post, endpoint)
      .to_return(status: 200, body: api_response.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '.search' do
    it 'sends a nearby search request with a location restriction and the API key' do
      described_class.search(35.6812, 139.7671, limit: 5, radius_km: 1)

      expect(
        a_request(:post, endpoint)
          .with(
            headers: { 'X-Goog-Api-Key' => 'test-key' },
            body: hash_including(
              'maxResultCount' => 5,
              'rankPreference' => 'DISTANCE',
              'languageCode' => 'ja',
              'locationRestriction' => {
                'circle' => {
                  'center' => { 'latitude' => 35.6812, 'longitude' => 139.7671 },
                  'radius' => 1000.0
                }
              }
            )
          )
      ).to have_been_made
    end

    it 'normalizes Google places into the GeoJSON shape the pipeline expects' do
      result = described_class.search(35.6812, 139.7671).first
      properties = result.data['properties']

      expect(result.data['geometry']['coordinates']).to eq([139.7671, 35.6812])
      expect(properties).to include(
        'osm_id' => 'google:ChIJabc123',
        'name' => 'Blue Bottle Coffee',
        'osm_value' => 'cafe',
        'city' => 'Chiyoda City',
        'state' => 'Tokyo',
        'country' => 'Japan',
        'postcode' => '100-0005',
        'street' => 'Marunouchi',
        'housenumber' => '1'
      )
    end

    context 'when the API returns an error' do
      before do
        stub_request(:post, endpoint).to_return(status: 403, body: 'forbidden')
      end

      it 'returns an empty array' do
        expect(described_class.search(35.6812, 139.7671)).to eq([])
      end
    end
  end
end
