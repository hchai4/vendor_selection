with vendor_pricing as (

    select *
    from {{ ref('stg_vendor_selection__vendor_pricing') }}

),

vendor_performance as (

    select *
    from {{ ref('stg_vendor_selection__vendor_performance') }}

),

vendor_manager as (

    select *
    from {{ ref('stg_vendor_selection__vendor_manager') }}

),

joined as (

    select
        vendor_pricing.create_time,
        vendor_pricing.country_code,
        vendor_manager.account_manager,
        vendor_pricing.vendor_id,
        vendor_pricing.product_id,
        vendor_performance.send_amount,
        vendor_performance.deliver_rate,
        vendor_pricing.rate
    from vendor_pricing
    left join vendor_performance
        on vendor_pricing.vendor_id = vendor_performance.vendor_id
       and vendor_pricing.country_code = vendor_performance.country_code
    left join vendor_manager
        on vendor_pricing.vendor_id = vendor_manager.vendor_id
       and vendor_pricing.country_code = vendor_manager.country_code

),

final as (

    select
        create_time,
        country_code,
        account_manager,
        vendor_id,
        product_id,
        send_amount,
        deliver_rate,
        rate,
        round(
            (
                (coalesce(deliver_rate, 0) / 100.0) * ln(1 + coalesce(send_amount, 0))
            ) / (1 + 10000 * coalesce(rate, 0)),
            4
        ) as score


    from joined

)

select *
from final
