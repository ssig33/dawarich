# frozen_string_literal: true

# Reverse geocodes coordinates to nearby POIs using the Google Places API (v1).
#
# Returns result objects that mimic Geocoder::Result (each responds to #data
# with a GeoJSON-like { 'geometry' => ..., 'properties' => ... } hash), so the
# rest of the reverse geocoding pipeline can consume Google results without any
# special-casing.
class ReverseGeocoding::Places::GoogleLookup
  ENDPOINT = 'https://places.googleapis.com/v1/places:searchNearby'
  FIELD_MASK = %w[
    places.id
    places.displayName
    places.location
    places.types
    places.primaryType
    places.addressComponents
  ].join(',').freeze

  Result = Struct.new(:data)

  def self.search(lat, lon, limit: 10, radius_km: 1)
    new(lat, lon, limit: limit, radius_km: radius_km).search
  end

  def initialize(lat, lon, limit: 10, radius_km: 1)
    @lat = lat
    @lon = lon
    @limit = limit
    @radius_m = radius_km * 1000.0
  end

  def search
    response = HTTParty.post(
      ENDPOINT,
      headers: headers,
      body: request_body.to_json,
      timeout: 10
    )

    unless response.success?
      Rails.logger.error("Google Places lookup failed (#{response.code}): #{response.body}")
      return []
    end

    Array(response.parsed_response['places']).map { |place| Result.new(normalize(place)) }
  rescue StandardError => e
    Rails.logger.error("Google Places lookup error for #{@lat},#{@lon}: #{e.message}")
    ExceptionReporter.call(e)
    []
  end

  private

  def headers
    {
      'Content-Type' => 'application/json',
      'X-Goog-Api-Key' => GOOGLE_PLACES_API_KEY,
      'X-Goog-FieldMask' => FIELD_MASK
    }
  end

  def request_body
    {
      maxResultCount: @limit,
      rankPreference: 'DISTANCE',
      languageCode: GOOGLE_PLACES_LANGUAGE,
      locationRestriction: {
        circle: {
          center: { latitude: @lat, longitude: @lon },
          radius: @radius_m
        }
      }
    }
  end

  # Maps a Google place into the same GeoJSON shape Photon/Geoapify return.
  def normalize(place)
    components = address_components(place)

    {
      'geometry' => {
        'coordinates' => [
          place.dig('location', 'longitude'),
          place.dig('location', 'latitude')
        ]
      },
      'properties' => {
        'osm_id'      => "google:#{place['id']}",
        'name'        => place.dig('displayName', 'text'),
        'osm_value'   => place['primaryType'] || place['types']&.first,
        'city'        => components['locality'] || components['postal_town'] ||
          components['administrative_area_level_2'],
        'country'     => components['country'],
        'state'       => components['administrative_area_level_1'],
        'postcode'    => components['postal_code'],
        'street'      => components['route'],
        'housenumber' => components['street_number']
      }
    }
  end

  # Flattens Google's addressComponents array into a { type => value } hash.
  def address_components(place)
    Array(place['addressComponents']).each_with_object({}) do |component, hash|
      Array(component['types']).each do |type|
        hash[type] ||= component['longText'] || component['shortText']
      end
    end
  end
end
