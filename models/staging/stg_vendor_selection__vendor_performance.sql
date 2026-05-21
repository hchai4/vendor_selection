with source as (

    select * from {{ source('vendor_selection', 'vendor_performance') }}

), 

renamed as (

    select
        id as vendor_id,
        country as country_code,
        send_amt as send_amount,
        deliver_rate,
        create_time
    from source
    where id is not null
      and country is not null
      and send_amt > 1000
      and date(create_time) between date_sub(current_date(), interval 6 month) and current_date()

)

select *
from renamed