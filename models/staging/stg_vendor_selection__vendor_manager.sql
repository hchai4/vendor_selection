with source as (

    select * from {{ source('vendor_selection', 'vendor_manager') }}

), 

renamed as (

    select
        vendor as vendor_id,
        country,
        account_manager
    from source
    where vendor is not null
      and country is not null

)

select *
from renamed