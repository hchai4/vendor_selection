with vendor_pricing as (

    select *
    from {{ ref('stg_vendor_selection__vendor_pricing') }}

),

valid_dates_vendor_pricing as (

    select
        vendor_id,
        product_id,
        country_code,
        rate,
        create_time as valid_from,

        -- use lead window function to get the next createdate of vendor price
        LEAD(create_time) OVER (
            PARTITION BY country_code, vendor_id, product_id
            ORDER BY create_time
        ) AS valid_to_raw
    from vendor_pricing

),

final_pricing as (

    select
        vendor_id,
        product_id,
        country_code,
        rate,
        valid_from,
        -- use coalesce to handle null value, i.e. newest price lead return to null
        coalesce(valid_to_raw, CAST('2099-12-31' as date)) as valid_to
    from valid_dates_vendor_pricing

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
        vp.valid_from,
        vp.valid_to,
        vp.country_code,
        vm.account_manager,
        vp.vendor_id,
        vp.product_id,
        vper.send_amount,
        vper.deliver_rate,
        vp.rate
    from final_pricing as vp
    join vendor_performance as vper
        on vp.vendor_id = vper.vendor_id
       and vp.country_code = vper.country_code
    join vendor_manager as vm
        on vp.vendor_id = vm.vendor_id
       and vp.country_code = vm.country_code

),


final as (

    select
        valid_from,
        valid_to,
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
