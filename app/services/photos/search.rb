# frozen_string_literal: true

class Photos::Search
  attr_reader :user, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @start_date = start_date
    @end_date = end_date
  end

  def call
    photos = []

    photos << request_immich if user.immich_integration_configured?
    photos << request_photoprism if user.photoprism_integration_configured?

    photos.flatten.map { |photo| Api::PhotoSerializer.new(photo, photo[:source]).call }
  end

  private

  def request_immich
    formatted_start_date = format_date_for_immich(start_date)
    formatted_end_date = format_date_for_immich(end_date)

    # If start_date and end_date are the same, set start_date to the previous day
    formatted_start_date = (Date.parse(formatted_start_date) - 1).to_s if formatted_start_date == formatted_end_date

    Immich::RequestPhotos.new(
      user,
      start_date: formatted_start_date,
      end_date: formatted_end_date
    ).call.map { |asset| transform_asset(asset, 'immich') }.compact
  end

  def format_date_for_immich(date_string)
    return nil unless date_string

    Date.parse(date_string).to_s
  end

  def request_photoprism
    Photoprism::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date
    ).call.map { |asset| transform_asset(asset, 'photoprism') }.compact
  end

  def transform_asset(asset, source)
    asset_type = asset['type'] || asset['Type']
    return if asset_type.downcase == 'video'

    asset.merge(source: source)
  end
end
