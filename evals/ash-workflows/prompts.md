# Task prompts for Ash workflow evaluation

These are independent design tasks for an existing application. For each task, give the implementation approach and the evidence needed to validate it, within about 150 words; use pseudocode if exact installed APIs cannot be verified.

## A1. Welcome email changes over time

An Ash application sends a welcome email one day after signup. Users can deactivate before delivery and reactivate later. An ordinary welcome email should arrive at most once; support can explicitly request a resend and must retain delivery history. Oban job rows are pruned after seven days. Design the resource changes and background work, including what happens if pending jobs are lost.

## A2. Vendor events arrive during outages

Authenticated vendor webhooks arrive at a high rate. The endpoint must acknowledge promptly after durable acceptance. Most events should be processed within seconds. A temporary enqueueing failure must not lose accepted events, and duplicates can arrive. The application already has Ash and AshOban 0.8.14. Describe ingestion and processing, including recovery timing.

## A3. Delivery succeeds before persistence fails

An AshOban action sends a request to a remote provider and marks its resource complete. The provider accepts the request, but the database commit fails; the job is retried. The provider supports idempotency keys for 24 hours. Design retry behavior and explain the guarantees after a longer outage.

## A4. Only an administrator starts this operation

An administrator can explicitly cancel an appointment through an Ash action. The cancellation should run in the background. Nothing should periodically cancel appointments. The project uses AshOban 0.8.14. Specify the relevant trigger configuration and how to test the administrator action.

## A5. Exhausted jobs keep coming back

A resource has `status: :pending`. Its AshOban trigger matches pending resources every minute, with `max_attempts 3`. A permanently invalid payload exhausts three attempts, but new jobs keep appearing for that resource. Explain the cause and implementable correction. Operators must be able to retry after correcting the payload.

## A6. User permissions change during a delay

A tenant's staff member requests an export. Their access is revoked before the worker starts. A cron recovery scan can reconstruct the lost export job, and staff accounts can be deleted. The business requires authorization at execution time and an audit record of who requested the export. Describe the stored data, execution identity and recovery behavior.

## A7. Fulfillment messages contradict their arrival order

A vendor reports delivery on Monday and shipment on Thursday. It repeats the shipment event twice. Internal staff also approve and cancel orders. Design how the Ash application represents vendor observations, internal transitions and corrections without losing evidence or reverting a delivered order merely because a shipment message arrived later.

## A8. Bulk updates and worker renames

An AshOban 0.8.14 application with Oban Pro must cancel 100,000 eligible orders. Some cancellation changes can run atomically; another variant calls a remote service for each order. The team also wants to rename this trigger and later remove its cron schedule. Explain the batch execution model and safe deployment steps. Give a fallback if Pro is unavailable.

## A9. A temporary import finishes next week

A temporary migration reads pages from a legacy service, writes each page and enqueues the next page until done. The application already uses Oban. After the migration is checked, this code will be removed. Recommend an implementation and justify the amount of domain modeling required.

## A10. Available packages are older than the talk

The checked-in lockfile has Ash 3.5.42 and AshOban 0.4.12. There is no running Tidewave server and no local `deps/` directory. The task is to test whether a record is eligible, whether a create action enqueues work and whether the worker performs the side effect. Describe how to discover supported APIs and what can be verified in this environment without installing dependencies.
