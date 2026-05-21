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
        vp.create_time,
        vp.country_code,
        vm.account_manager,
        vp.vendor_id,
        vp.product_id,
        vper.send_amount,
        vper.deliver_rate,
        vp.rate
    from vendor_pricing as vp
    join vendor_performance as vper
        on vp.vendor_id = vper.vendor_id
       and vp.country_code = vper.country_code
    join vendor_manager as vm
        on vp.vendor_id = vm.vendor_id
       and vp.country_code = vm.country_code

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
        ) as score,
        row_number() over (
            partition by country_code, vendor_id
            order by round(
                (
                    (coalesce(deliver_rate, 0) / 100.0) * ln(1 + coalesce(send_amount, 0))
                ) / (1 + 10000 * coalesce(rate, 0)),
                4
            ) desc,
            product_id
        ) as product_rank
    from joined

)

select *
from final
