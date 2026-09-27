"""Responsive table (P0.8c): a real table from `md` up, a list of cards below it.

Both views render from the same columns and rows. Only one is displayed at a time (CSS
`hidden`), so screen readers see a single copy. Each card labels every value with its
column name, so nothing is lost on a phone.
"""

import from ...components.ui.table {
    Table,
    TableHeader,
    TableBody,
    TableRow,
    TableHead,
    TableCell
}

# columns: [{"key": ..., "label": ...}]; rows: [{key: value}], with a unique `row_key`.
def:pub ResponsiveTable(
    columns: list[dict[str, str]],
    rows: list[dict[str, str]],
    caption: str,
    row_key: str = "id"
) -> JsxElement {
    return
        <div className="flex flex-col gap-3">
            <div
                data-testid="responsive-table"
                className="hidden overflow-hidden rounded-lg border bg-card md:block"
            >
                <Table>
                    <caption className="sr-only">{caption}</caption>
                    <TableHeader>
                        <TableRow>
                            {[
                                <TableHead key={col["key"]} className="px-4">
                                    {col["label"]}
                                </TableHead> for col in columns
                            ]}
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {[
                            <TableRow key={row[row_key]}>
                                {[
                                    <TableCell key={col["key"]} className="h-12 px-4">
                                        {row[col["key"]]}
                                    </TableCell> for col in columns
                                ]}
                            </TableRow> for row in rows
                        ]}
                    </TableBody>
                </Table>
            </div>
            <ul
                data-testid="responsive-table-cards"
                aria-label={caption}
                className="flex flex-col gap-3 md:hidden"
            >
                {[
                    <li key={row[row_key]} className="rounded-lg border bg-card p-4">
                        <dl
                            className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm"
                        >
                            {[
                                <div key={col["key"]} className="contents">
                                    <dt className="text-muted-foreground">
                                        {col["label"]}
                                    </dt>
                                    <dd className="min-w-0 break-words font-medium">
                                        {row[col["key"]]}
                                    </dd>
                                </div> for col in columns
                            ]}
                        </dl>
                    </li> for row in rows
                ]}
            </ul>
        </div>;
}
