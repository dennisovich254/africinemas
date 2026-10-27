"""The same snack picker and payment flow on private tickets and at the counter."""

import from react { useState }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ..backoffice.SnackOnlySale { SnackOnlySale }

def:pub MoreSnacks(slug: str, token: str, on_paid: any) -> JsxElement {  # jac:ignore[W1037]
    [opened, set_opened] = useState(False);
    return
        <section
            id="more-snacks"
            className="flex flex-col gap-4 print:hidden"
            data-testid="more-snacks"
        >
            <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                    <h2 className="text-lg font-semibold">More snacks?</h2>
                    <p className="text-sm text-muted-foreground">
                        Add them before your showtime starts. Pay only for what you add.
                    </p>
                </div>
                {not opened
                    and <Button
                        className="min-h-11"
                        data-testid="add-more-snacks"
                        onClick={lambda { set_opened(True); }}
                    >
                        Add snacks
                    </Button>}
            </div>
            {opened
                and <SnackOnlySale
                    slug={slug}
                    booking_token={token}
                    on_paid={on_paid}
                />}
        </section>;
}

def:pub CounterMoreSnacks(slug: str) -> JsxElement {
    [reference, set_reference] = useState("");
    [chosen, set_chosen] = useState("");

    def typed(e: any) {  # jac:ignore[W1037]
        set_reference(e.target.value);
    }

    def find(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_chosen(reference.strip().upper());
    }
    return
        <section className="flex flex-col gap-4" data-testid="counter-more-snacks">
            <h2 className="text-lg font-semibold">Add snacks to a booking</h2>
            <form onSubmit={find} className="flex flex-col gap-2 sm:max-w-md">
                <Label htmlFor="extra-booking-reference">Booking reference</Label>
                <div className="flex gap-2">
                    <Input
                        id="extra-booking-reference"
                        value={reference}
                        onChange={typed}
                        autoComplete="off"
                        className="h-11 min-w-0 text-base"
                    />
                    <Button
                        type="submit"
                        className="min-h-11"
                        disabled={len(reference.strip()) == 0}
                    >
                        Find booking
                    </Button>
                </div>
            </form>
            {len(chosen) > 0
                and <SnackOnlySale
                    key={chosen}
                    slug={slug}
                    booking_reference={chosen}
                />}
        </section>;
}
