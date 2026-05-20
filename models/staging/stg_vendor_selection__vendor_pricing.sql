with source as (

    select *
    from {{ source('vendor_selection', 'vendor_pricing') }}

), 

renamed as (

    select
        vendor_id,
        product_id,
        country_code,
        rate
    from source
    where vendor_id is not null
      and product_id is not null
      and country_code is not null
      and rate <= 0.1


)

select *
from renamed
